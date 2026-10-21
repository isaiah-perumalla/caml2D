# Design choices

Notes on how the simulation is structured and why. Sections marked
**(planned)** describe the intended direction, not code that exists yet.

## Module layout

| Module | Role |
|---|---|
| `Vec2` | Immutable 2D vector for single values (positions in the API, gravity) |
| `Vecarray` | Flat typed-array vectors: `Float32Vec` (1D) and `Float32Vec2` (interleaved x, y), with whole-array operations |
| `Pool` | Generic pool of fixed-size elements (`Pool.Make (S : SIZED)`) |
| `Positions.Linear` | Verlet integrator for linear motion: positions, prior positions, inverse mass |
| `Positions.Angular` | **(planned)** the same for rotation: angle, prior angle, inverse inertia |
| `Rigid` | **(planned)** shapes (circles first) and their geometry |
| `Collision` | **(planned)** detection and resolution, including walls |
| `Particles` | Current demo world: integration, springs, walls. To be replaced by `Rigid` + `Collision` |
| `Renderer` | Draws a source of points through a backend (`HtmlCanvas` in `web/`) |

## Data layout: one array per property

Body state is stored as flat typed arrays, one per property, not as an array
of records. Positions are a single interleaved `Float32Vec2` (`x0 y0 x1 y1 …`),
inverse masses a `Float32Vec`, and so on.

- Under js_of_ocaml these are `Float32Array`s, so there's no per-body
  allocation and loops walk contiguous memory.
- Shapes follow the same rule: one module per shape type holding many bodies
  (`Circles`, later `Boxes`), not a variant per body such as
  `Circle of … | Box of …`, which would put a branch in every loop.

## `Positions.Linear`

- **A pure integrator.** It owns positions, prior positions and inverse mass,
  and knows nothing about the world (no bounds, no shapes).
- **Verlet:** `x' = 2x − prev + (f·inv_mass + g)·dt²`. Velocity is implicit in
  `pos − prev`.
- **In place, no scratch buffers.** The new position is written straight into
  the prior-positions buffer, then the two refs are swapped:
  1. `scale_add`: `prev := 2·pos − prev`
  2. `acc_scale_by`: `prev := prev + f·inv_mass·dt²`

  Each element reads its own inputs before writing, so working in place is
  safe. This replaced an earlier version that took scratch buffers from a
  pool, and is about 40% faster (see benchmarks).
- **Immovable bodies** have `inv_mass = 0`: the force term vanishes, and gravity
  must be masked out for them.
- **Gravity (planned): passed to `integrate`, not `init`.**
  - Gravity is an external input to a step, like `forces` and `dt`, so
    `Linear` keeps no world state. `Angular` will take torques the same way.
  - Changing gravity at runtime, or testing with several values, is just a
    different argument.
  - It can't be folded into `forces` by the caller: the equivalent force is
    `g / inv_mass`, undefined for immovable bodies.
  - Planned as part of the accumulate pass, so it doesn't cost a third pass:
    `prev += (f·m + g·[m ≠ 0])·dt²`.
  - Not a functor over gravity: see "Functors and inlining" below.
- **Buffer access (planned):** expose `positions` and `prior_positions` as raw
  `Float32Vec2.t`. The renderer needs the whole positions buffer each frame,
  and collision resolution and walls write both buffers in bulk. Per-index
  getters return a fresh `Vec2.t` each call, which is too slow for that.
  Buffers are swapped by `integrate`, so callers must fetch them again after
  each step rather than keep them.

## `Rigid` and `Collision` (planned)

### One shared `Linear.t` for all bodies

The world holds a single `Linear.t` for every body, whatever its shape. Shape
modules hold only geometry plus each shape's body index into it:

```ocaml
type world = {
  linear  : Positions.Linear.t;  (* every body: position, prior, inv_mass *)
  circles : Rigid.Circles.t;     (* radius.(k), body.(k) *)
  boxes   : Rigid.Boxes.t;       (* half extents, body.(k) *)
}
```

- Integration is one pass over all bodies.
- Contacts are plain body indices into one array, so resolution doesn't need
  to know shape types.
- Rendering reads one positions buffer plus each shape's geometry.

The alternative, each shape module owning its own `Linear.t`, would make
every cross-shape contact track which array each side belongs to.

### Detection is shape-specific; resolution is shared

Each pair of shape types gets a test that only reports a contact:

```ocaml
type contact = {
  a : int; b : int;         (* body indices *)
  nx : float; ny : float;   (* unit normal, from a to b *)
  depth : float;            (* overlap *)
  (* later: contact point, for rotation and friction *)
}

val circle_circle : … -> contact option
val circle_box    : … -> contact option
val box_box       : … -> contact option   (* separating axis test *)
```

One shared function resolves any contact:

```ocaml
val resolve : Positions.Linear.t -> contact -> unit
```

- N shape types need N·(N+1)/2 pair tests but only one `resolve`.
- When `Angular` arrives, only `resolve` changes, to apply torque at the
  contact point.

### Resolution: move positions, not velocities

With Verlet there's no need for impulses. Overlapping bodies are moved apart
along the contact normal, split by `inv_mass` (immovable bodies don't move),
and their velocity changes automatically because it is `pos − prev`. A few
iterations per step settle stacks. This is the usual approach for Verlet
simulations (position-based dynamics).

### Finding candidate pairs

Checking every pair is n²/2: about 50 million checks per step at 10k bodies,
well past the time budget. Detection is therefore split in two:

```ocaml
val candidate_pairs : … -> (int -> int -> unit) -> unit  (* cheap first pass *)
val resolve_pair    : … -> int -> int -> unit            (* exact test + push apart *)
```

- Start with checking every pair, then replace the first pass with a uniform
  grid / spatial hash (cells about one diameter wide) without changing callers.
- The grid works on axis-aligned bounding boxes tagged `(kind, local index)`,
  so it handles every shape type. One `match` on the two kinds picks the exact
  test; that is the only place shape types meet.

### Walls

Walls are collisions against fixed boundaries, not part of integration. Using
each body's own radius removes the current workaround in `web/main.ml` of
shrinking the box by one shared radius.

### Difficulty

- Circle–circle and circle–box: short (distance check; closest point on box).
- Box–box: separating axis test plus contact points, and only meaningful once
  boxes rotate, so it depends on `Angular`. By far the most work.

### Migration from `Particles`

Before deleting `Particles`:

- **Springs:** move them to a constraints module, or drop them.
- **Wind:** becomes an added force.
- **Renderer:** `circles` uses one shared radius. `SOURCE` needs per-body
  radii.
- **Tests:** the wall, corner, sideways-floor and immovable tests in
  `test_caml2d.ml` move to `Rigid` / `Collision`.

Suggested order: `Linear` gravity and buffer access → `Rigid.Circles` →
walls in `Collision` (port wall tests) → circle–circle → switch `web/` over
and delete `Particles` → spatial grid.

## Performance findings

Measured with Node 18 on the release build (`dune build --profile release`),
each case in its own Node process. Absolute numbers will differ in a browser;
the ratios are the point.

### Fewer passes over the arrays matter most

ns per particle per step:

| | 10k | 100k |
|---|---|---|
| `Linear`, three passes + pooled scratch buffers | 115–148 | 127–159 |
| `Linear`, two passes, in place (current) | 68–80 | 76–95 |
| One fused loop, same maths (reference) | 41–52 | 58–69 |

- Every element access in js_of_ocaml goes through a bounds-checked
  `get(offset(i))` / `set(offset(i), v)` call, so each extra pass repeats that
  cost for every element.
- Removing cheap passes (`TypedArray.fill` zeroing, a plain `scale`) made
  little difference; removing passes that make per-element calls did.
- At 100k bodies and 120 Hz physics (two steps per 60 fps frame), the current
  `Linear` is about 16–20 ms per frame, right at the budget, before drawing.
  A single fused `verlet` operation would roughly halve that.

### float32 vs float64

`Float64Array` was the same speed or 5–15% slower. In V8, converting to
float32 on store is one CPU instruction, while float64 doubles memory traffic.
float32 stays the default. Switch positions only to float64 if slow particles
jitter: Verlet's `pos − prev` in float32 near x = 1000 is only accurate to
about 6×10⁻⁵.

### Functors and inlining

- In the release build, js_of_ocaml inlines `V2`/`V1` accessors into callers
  in plain modules such as `Positions`, including through `Float32Vec2`'s
  sealed signature.
- In `Particles` (a functor applied inside `main`) the `getx`/`gety`/`set`
  wrappers stayed as separate calls.
- So the physics core is kept in plain modules, not functors. The world
  constants a functor would fold in are not worth the lost inlining.

### Inlining can change unexpectedly

When `Linear` stopped calling `V2.scale`, js_of_ocaml inlined it into
`Particles.integrate` (its only remaining caller). That made the hot loop's
function larger and 40–50% slower in V8, though `particles.ml` itself hadn't
changed. The call was dead code and removing it fixed the regression. Lesson:
re-measure after refactors, and compare against the previous commit by
alternating runs.

### Pool

- `Pool.Make` hands out fixed-size elements up to a capacity. `acquire` doesn't
  zero reused elements (fresh ones come from `make`, which does).
- No longer used by `Linear`, which allocates its buffers once in `init`.
  Allocating a typed array per step was a measurable cost (and a leak
  in `Particles` until removed).
