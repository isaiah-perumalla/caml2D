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
| `Area` | Regions (boxes; circles planned) that add forces to the bodies inside them |
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
- **Verlet:** `x' = 2x − prev + f·inv_mass·dt²`. Velocity is implicit in
  `pos − prev`.
- **In place, no scratch buffers.** The new position is written straight into
  the prior-positions buffer, then the two refs are swapped:
  1. `scale_add`: `prev := 2·pos − prev`
  2. `acc_scale_by`: `prev := prev + f·inv_mass·dt²`

  Each element reads its own inputs before writing, so working in place is
  safe. This replaced an earlier version that took scratch buffers from a
  pool, and is about 40% faster (see benchmarks).
- **Immovable bodies** have `inv_mass = 0`, so every force on them is
  multiplied by zero and they never move.
- **Only forces, no accelerations.** `integrate : t -> forces:forces -> float
  -> unit`. Mass-independent accelerations such as gravity are converted to
  forces by whoever produces them: `f = a / inv_mass`, skipped when
  `inv_mass = 0`. This was chosen over:
  - an `accelerations` buffer passed to `integrate`, which would either be
    masked by `inv_mass` inside `Linear` or require every caller to keep it
    zero for immovable bodies (an extra pass, or an unchecked rule);
  - a gravity parameter on `init`, which would put world state in the
    integrator.

  The cost is one division per affected body in the code that writes forces,
  which therefore needs each body's `inv_mass`.
- Not a functor over gravity or any other world constant: see "Functors and
  inlining" below.
- **Buffer access (planned):** expose `positions` and `prior_positions` as raw
  `Float32Vec2.t`. The renderer needs the whole positions buffer each frame,
  and collision resolution and walls write both buffers in bulk. Per-index
  getters return a fresh `Vec2.t` each call, which is too slow for that.
  Buffers are swapped by `integrate`, so callers must fetch them again after
  each step rather than keep them. An `inv_masses` accessor would likewise let
  force producers such as `Area` read inverse masses without going through
  `get_inv_mass` per body.

## `Area`

A region of the world that adds forces to the bodies inside it.

```ocaml
type params = { forces : Vec2.t; drag_const : float; gravity : Vec2.t }
type shape =
  | Box of { top_left : Vec2.t; bottom_right : Vec2.t }
  | Circular of { center : Vec2.t; radius : float }
type t = { params : params; shape : shape }

val acc_forces :
  area:t -> pos:Positions.Linear.t -> target:Positions.Linear.forces -> unit
```

- **A variant per area is fine here**, unlike for bodies: there are only a few
  areas, so one `match` per area per step costs nothing.
- **"Inside" means the body's centre is inside.** y grows downwards, as on the
  canvas, and edges count as inside.
- **`acc_forces` accumulates** into `target`, so wind, springs and several
  overlapping areas add up.
- **Gravity is an acceleration**, applied as the force `gravity / inv_mass` so
  bodies of any mass accelerate the same; immovable bodies get none.
- **Not done yet:** `Circular` areas (currently no effect) and `drag_const`,
  which needs velocity `(pos − prev) / dt`, so prior positions and `dt`.
- **The step order** each frame: clear forces → areas add forces → springs,
  if kept → `Linear.integrate` → collisions.

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

Suggested order: `Linear` buffer access → `Rigid.Circles` →
walls in `Collision` (port wall tests) → circle–circle → switch `web/` over
and delete `Particles` → spatial grid.

## Performance findings

Unless a section says otherwise, measured with Node 18 on the release build
(`dune build --profile release`), each case in its own Node process.
Absolute numbers will differ in a browser; the ratios are the point.

**Node 18's V8 (2022) is much older than Chrome's,** and overstates the cost
of allocation and of crossing function boundaries. The `resolve` comparison
below was rerun in Chrome 156, and its results differ markedly from Node's.
Benchmark in Chrome for anything allocation-sensitive.

### How the benchmarks were run

A throwaway harness, not in the repo: a copy of `lib/` plus one
js_of_ocaml executable (`(modes js)`, `(libraries caml2d js_of_ocaml)`),
built with `--profile release` and run with `node`. For each case it:

1. builds the data (bodies on a grid, `inv_mass` 1);
2. runs a tenth of the steps to warm up the JIT;
3. times the remaining steps with `performance.now()`;
4. reports ms per step and ns per body.

Each case takes a name argument so it can run in its own Node process, so one
case's JIT state can't affect another.

When comparing two versions, the two builds were run alternately three times.
Run-to-run variance on this machine (WSL) is 10–30%, so only differences
larger than that are reported as real. A loop with identical JS in both
builds was included as a noise baseline.

**In Chrome:** the same benchmark built as a page (the case from the URL's
query string, the result written into the page), run in headless Chrome
from WSL:

- **timing:** `chrome.exe --headless=new --dump-dom "file:///…/index.html?case"`,
  one fresh browser per case, with no profiling;
- **memory and GC:** a PowerShell script (`cdp-bench.ps1`) on the Windows side
  drives Chrome's DevTools protocol, because Windows Chrome's debugging port
  isn't reachable from WSL. Per case it starts a fresh headless Chrome, runs
  the sampling heap profiler with collected objects included
  (`includeObjectsCollectedByMinorGC`/`MajorGC`), traces
  `devtools.timeline,v8,disabled-by-default-v8.gc`, and counts the
  `MinorGC`/`MajorGC` events on the page's main thread (`CrRendererMain`).
  Profiling slows allocation-heavy code, so times from these runs are not
  used; times come from the unprofiled runs.

V8's `--trace-gc` doesn't work for this on Windows: it prints to the renderer
process's standard output, which a GUI Chrome discards.

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

### `Area.acc_forces`: match on the shape outside the loop

ns per body, one box area, three alternating runs:

| | Before, 10k | After, 10k | Before, 100k | After, 100k |
|---|---|---|---|---|
| All bodies inside | 41–53 | 22–24 | 40–46 | 28–35 |
| Half inside | 26–33 | 16–25 | 26–35 | 18–20 |
| None inside | 17–23 | 8–9 | 18–21 | 7–8 |

- **Before:** `contains area.shape` returned a closure, called once per body.
  js_of_ocaml can't inline a function chosen at run time, so every body paid
  a generic call, even when none were inside.
- **After:** `match area.shape` once, with one loop per shape and the bounds
  in local floats. The test compiles to four comparisons in the loop, and the
  force update is inlined too.
- At 100k bodies an area covering everything now costs about 35–45% of a
  `Linear.integrate` step, down from about 60%.
- In the benchmark the whole call was inlined with the area's values folded
  in as constants. Areas built at run time won't get that, so expect slightly
  less. The "none inside" gain comes from removing the closure, which applies
  either way.
- **Next:** visit only bodies near the area via the planned spatial grid, so
  cost scales with the bodies inside, not with all bodies.

### Asserts: `-noassert` makes no measurable difference

dune's release profile does not pass `-noassert`; asserts stay in the JS
(confirmed by their `Assert_failure` locations in the output). Building with

```
(env (release (flags (:standard -noassert))))
```

removed them all, but `acc_forces` and `Linear.integrate` timings stayed
within the noise baseline. An assert is a couple of integer comparisons with a
branch that's never taken, which is cheap next to a closure call or a
bounds-checked Bigarray access. Asserts are kept in every profile, and the
assert-based tests stay valid.

### Rejected: packing two floats into one `int64` (`Pair.FloatPair`)

The idea was to store a pair of floats as one 64-bit value: each float
narrowed to float32 with `Int32.bits_of_float`, the two 32-bit patterns
combined with shifts and masks.

Benchmarked against a float record (`{ first : float; second : float }`) and
a tuple, 1 million pairs, three runs each, ns per pair:

| Release JS (Node 18) | make + read | store in array | read stored |
|---|---|---|---|
| `int64` packing | 99–109 | 366–389 | 42–52 |
| float record | 53–67 | 286–314 | 32–36 |
| tuple | 45–48 | 270–403 | 30–31 |

| Native | make + read | store in array | read stored |
|---|---|---|---|
| `int64` packing | 18–23 | 69–85 | 17–22 |
| float record | 10–13 | 59–68 | 15–18 |
| tuple | 11–12 | 150–177 | 16–17 |

- **Slower everywhere:** about 1.7–2× slower to make and read than a float
  record, in JS and native builds.
- **Why, in JS:** js_of_ocaml emulates `Int64` as an object with three 24-bit
  parts, so every value is an allocation and every shift, mask and float
  conversion is a runtime call. JavaScript's BigInt is not used for it.
- **Why, natively:** an `int64` is still boxed when stored, and the bit
  conversions are extra work a record doesn't need.
- **Precision:** each float is narrowed to float32, so values like `0.1` come
  back rounded.
- **No allocation saved:** the packing, the record and the tuple all allocate
  one heap value per pair.
- **Tuples natively:** worst at storing (150–177 ns), because each float in a
  tuple is boxed separately; a float record keeps both unboxed in one block.
  In JS, where every float is a plain number, the difference disappears.

**BigInt was considered and not tried.** js_of_ocaml has no typed binding for
it, so it would need either `Js.Unsafe` (untyped, and JS-only, so the native
tests couldn't use it) or `external` declarations with a JavaScript stub file
plus matching C stubs for native builds, i.e. the logic written twice. BigInts
are heap objects too, so it would still allocate per pair, and crossing between
OCaml and JS costs a call. Expected to beat the emulated `Int64` but not a
float record; not measured.

**What to use instead:**

- For a pair value: a float record. Fastest or close to it everywhere, full
  precision, no bit manipulation.
- For many pairs without per-pair allocation (e.g. collision contacts): typed
  arrays plus a count, such as `Vecarray.Float32Vec2` or one array per field.
  They work the same in native and JS builds.

### `Vec2`: abstract type, record implementation

`Vec2.t` is abstract in `vec2.mli`, with `x`/`y` accessors, so a different
implementation can be swapped in later. Callers use `Vec2.x v` rather than
`v.x`.

**The abstraction costs nothing at run time.** In a release-build probe, with
`Vec2` in a separate library used only through its `.mli`:

```js
// Vec2.x v *. 3. +. Vec2.y v *. 7.   →
d = d + c[1]*3. + c[2]*7.            // direct field reads, no calls
// Vec2.length (Vec2.add a b)          →
Math.sqrt(L*L + aP*aP)               // both inlined, no intermediate vector
```

js_of_ocaml optimises the whole program, so the `.mli` doesn't hide small
function bodies from it. This holds as long as the implementation's functions
stay small and the module is chosen at build time (not passed through a
functor applied inside a function, nor as a first-class module). Dev builds
don't inline.

### Rejected: a `Vec2` packed into one float64

The idea: store `x` and `y` as two float32s in the 8 bytes of one float64
(through a shared `ArrayBuffer` with `Float32Array`/`Float64Array` views), so
in JS a vector is a plain number and creating one allocates nothing.

Benchmarked against the record, 1 million vectors, release build, Node 18,
three runs, ns per vector:

| | Record | Packed |
|---|---|---|
| make + read `x`/`y` | 3.5–5.2 | 17–26 |
| `add` / `scale` / `magnitude` | 9.5–14 | 50–60 |
| read stored vectors | 5.8–6.2 | 3.3–6.1 |

- **4–6× slower** to create vectors and do arithmetic. Every `x`, `y` and
  `v` writes into the shared typed array and reads back the other view; a
  record read is `c[1]`.
- **The saved allocation was cheap.** V8 allocates short-lived objects
  quickly, and in this simple loop may skip creating some vectors entirely
  (3.5 ns for record make + read). In heavier code it doesn't: in `resolve`
  under Chrome, every `Vec2` was allocated (see below).
- **Reading stored vectors is no slower,** because a JS array of numbers is
  stored compactly. But bulk per-body data already lives in typed arrays
  (`Vecarray`), not in arrays of `Vec2`.
- **Precision drops to float32** for every vector, including area bounds and
  gravity.
- **JS only.** The library is also built natively for the tests, so using it
  would need a dune virtual library (`virtual_modules vec2`, one
  implementation per build), not a direct swap.

**The GC trade-off.** Packing trades a higher cost per operation for avoiding
garbage. In V8 that garbage is cheap to collect: a minor collection only
copies objects still in use, so short-lived vectors cost little to reclaim.
Measured in Chrome (below), minor collections averaged about 0.1 ms, but
individual ones reached 2–3 ms, which matters at high frame rates if they
are frequent. Long pauses otherwise come from long-lived data in full
collections, which temporary vectors don't add to. The per-body hot loops don't use `Vec2` anyway. If GC pauses ever
show up in the profiler (Performance panel, "Minor GC" in the Main track),
the fix is to remove allocation from that hot path, not to change every
vector's representation.

A note for js_of_ocaml 6: typed arrays are created with constructors
(`new%js Typed_array.float32Array_fromBuffer buf`); there are no
`Typed_array.Float32Array` modules, and `Typed_array.set`/`unsafe_get` take
and return JS numbers (`Js.float` / `Js.to_float`).

### `resolve`: raw floats vs `Vec2` vs packed vectors, in Chrome

Three versions of `Collision.Resolver.apply`, on the same contacts:

- **raw:** the current code, reading and writing `x`/`y` floats directly;
- **`Vec2`:** the same maths with `Vec2` records (`get`, `sub`, `scale`,
  `dot`, about 13 vectors per contact);
- **packed:** the same maths with the packed float64 vector.

Contacts: circles in a row, radius 1, 1.5 apart, each overlapping its
neighbour; alternate velocities, so half the pairs bounce. `detect` runs once,
then `resolve` repeatedly on the same contacts. Headless Chrome 156, release
build, a fresh browser per measurement, three runs.

**Time, ns per contact** (unprofiled runs):

| Contacts | Raw | `Vec2` | Packed |
|---|---|---|---|
| 1,999 (2,000 `resolve` calls) | 109–122 | 122–133 | 194–212 |
| 10,000 (500 calls) | 118–123 | 127–135 | 202–215 |
| *Node 18, 1,999, for comparison* | *244–300* | *437–496* | *417–477* |

**Memory and GC** (profiled runs; about 4.4 million contact resolutions at
1,999 contacts, 5.5 million at 10,000):

| | Raw | `Vec2` | Packed |
|---|---|---|---|
| Allocated, 1,999 contacts | 194–198 MB | about 2,150 MB | about 549 MB |
| Allocated, 10,000 contacts | 318–322 MB | 2,924–2,970 MB | 734–744 MB |
| Minor collections, 10,000 | 318–322 | 2,972–3,027 | 732–745 |
| Total GC pause, 10,000 | 31–32 ms | 246–304 ms | 64–70 ms |
| Longest pause, 10,000 | 1.7–2.0 ms | 1.8–2.6 ms | 1.8–2.1 ms |

Each total includes the same one-off setup: creating the circles and the
initial `detect` (about 50 million pairs at 10,000 contacts). Measured on its
own (no `resolve` calls), that is only **3.4 MB and 3 minor collections**, so
nearly everything in the table is `resolve` itself: at 10,000 contacts about
57 bytes per contact for raw, 530 for `Vec2` and 133 for packed.

- **`Vec2` costs little time but a lot of garbage.** It's only 5–15% slower
  than raw, but allocates about 9–11× as much and causes about 9–11× as many
  minor collections. Its vectors are not optimised away. Each collection is
  just as short; there are just many more of them, and their time is already
  inside its time per contact.
- **Packed is the slowest** (about 1.7–1.8× raw) and still allocates more than
  raw (about 2.3–2.8×), because its floats are boxed too (see below).
- **Raw is fastest and allocates least,** but still about 57 bytes per
  contact, roughly four or five boxed floats (see below).
- **Node 18 was misleading:** there `Vec2` looked about 2× slower than raw.
  Chrome's newer V8 is about twice as fast overall and much better at
  handling the record version.

**At 2,000 contacts per step and 120 Hz** (240,000 contacts a second), `Vec2`
would add roughly 110 MB/s of garbage and 100+ minor collections a second
(about 10 ms of GC per second) compared with raw. That fits in the frame
budget, but as frequent short pauses.

**Why even raw allocates: HeapNumbers.** In V8, a JS value is either a small
integer packed into the value itself or a pointer to a heap object. A float
doesn't fit the first form, so wherever V8 must store a float as an ordinary
value, it allocates a small heap object for it (a HeapNumber). Optimised code
avoids this inside one function and the functions it inlines, keeping
floats in registers. Floats get boxed at the edges:

- a float passed to or returned from a function that wasn't inlined;
- a float stored in an ordinary JS array or object, such as an OCaml ref or
  record (both arrays in js_of_ocaml), unless V8 has specialised it for
  floats;
- code that isn't optimised yet.

The compiled raw `resolve` has no OCaml-level allocation: every float is a
plain JS number. But each read goes through several calls before it reaches
the Float32Array:

```js
function getx(t, i){ var base = i * 2 | 0; return caml_ba_get_1(t, base); }
function caml_ba_get_1(ba, i0){ return ba.get(ba.offset(i0)); }
class Ml_Bigarray_c_1_1 extends Ml_Bigarray {
  offset(arg){ if(typeof arg !== "number") …; if(arg < 0 || arg >= this.dims[0]) caml_array_bound_error(); return arg; }
  get(ofs){ return this.data[ofs]; }     // the Float32Array read
  set(ofs, v){ this.data[ofs] = v; return 0; }
}
```

The next section shows that this access path is where the boxing comes from.

### Typed arrays read directly: where the boxing comes from

Two hypotheses for raw `resolve`'s allocation:

1. **V8's inlining limit.** In Node 18, `--trace-turbo-inlining` showed V8
   inlining only some of the calls in the loop (2 of 8 `update_add_i`, 1 of
   4 `velx`/`vely`) and stopping at its total inlining limit. Raising the
   limit (`--max-inlined-bytecode-size-cumulative=20000
   --max-inlined-bytecode-size=2000`) made raw 2.5× faster (52 vs 124–154 ns
   per contact) and cut its allocation by about 85% (85–89 vs 522–637 MB).
   Packed barely changed (228 vs 245 ns; 970 vs 1,331 MB).
2. **The Bigarray access path itself** (`getx` → `caml_ba_get_1` →
   `ba.offset`/`ba.get`).

Variants to separate them, in the same Chrome benchmark:

- **`…1` (per-contact function):** the loop body moved into its own function
  taking only ints, called through a ref so js_of_ocaml can't inline it back
  (it does, otherwise; `Sys.opaque_identity` didn't stop it). V8 then
  optimises the body with its own inlining limit, and only ints cross the
  call. This tests hypothesis 1.
- **`rawt`:** the Float32Array (or Int32Array) behind each Bigarray, taken
  once per call with `Typed_array.from_genarray`, read with
  `Typed_array.unsafe_get` and written with `Typed_array.set`, which compile
  to plain `p[i]`. All the maths is in the loop body, which has no calls.
  This tests hypothesis 2.
- **`packedt`:** packed vectors loaded and stored whole through Float64Array
  views (`new Float64Array(f32.buffer)`) of the same interleaved float32
  buffers. The packed operations (`add`, `sub`, `scale`, `dot`) are still
  calls: js_of_ocaml doesn't inline them.
- **none:** setup and `detect` only, no `resolve` calls.

The benchmark reached the buffers behind the abstract types with `Obj`. A
check run confirmed `rawt`, `packedt` and `packed` give exactly the same
positions and prior positions as `Collision.Resolver.apply` (maximum
difference 0, over three passes).

Headless Chrome 156, 10,000 contacts, 550 `resolve` calls (about 5.5 million
contact resolutions). Times from three unprofiled runs, memory from two
profiled runs:

| Variant | ns per contact | Allocated | Minor collections |
|---|---|---|---|
| none (setup and `detect` only) | – | 3.4 MB | 3 |
| raw (the library code) | 116–123 | 317–322 MB | 318–322 |
| raw1 (per-contact function) | 112–120 | 314–316 MB | 314–315 |
| `Vec2` | 124–140 | about 2,900 MB | about 2,935 |
| vec21 (per-contact function) | 133–135 | about 2,700 MB | about 2,722 |
| packed | 206–216 | 724–735 MB | 723–733 |
| packed1 (per-contact function) | 211–223 | 724–728 MB | 724–725 |
| **rawt** (direct typed arrays) | **18–19** | **4.0–4.3 MB** | **4** |
| **packedt** (direct typed arrays) | **113–114** | **8.6–8.7 MB** | **8** |

- **The per-contact function changes nothing,** for any variant. In Chrome
  the boxing isn't caused by V8's inlining limit; the Node 18 trace doesn't
  carry over.
- **Reading the typed arrays directly removes the boxing.** `rawt` allocates
  under 1 MB above the setup over 5.5 million contacts, effectively zero.
  `packedt` allocates about 1 byte per contact, even though it still calls
  the packed operations, so those calls weren't the problem either. The
  allocation comes from the Bigarray access path.
- **Why that path boxes:** the bounds check in `ba.offset`, which keeps the
  read behind several calls. See the next section: typed-array storage with
  the same kind of check allocates just as much.
- **`rawt` is about 6× faster than the library code** (19 vs 118 ns per
  contact). The current `resolve` mostly pays for the access path, not the
  maths.
- **Packed with direct access** no longer allocates, but at 114 ns it's still
  6× slower than `rawt`. That gap is the scratch-buffer round trip in every
  `x`/`y`/`v`: `f32`/`f64` are globals, so V8 has to keep every write to
  them, and can't keep the components in registers. Packing helps loads and
  stores (one per vector instead of two), not arithmetic.

**Decision** (the storage part is superseded by the next section):

- Hot loops should not read floats through Bigarray `get`/`set`.
- Keep raw floats for the arithmetic. Packed vectors are rejected: even
  without boxing they're 6× slower.
- `Vec2` is acceptable where the number of calls is modest (setup, area
  parameters, tests, a few hundred contacts).
- `detect` reads its floats through the same Bigarray path. It allocated
  little here (3.4 MB including setup, over about 50 million pairs), so
  measure it before changing it.

### Storage: typed arrays behind `Vecarray`, via a virtual library

Instead of hand-writing hot loops against typed arrays, change the storage
under `Vecarray` and leave every module above it as it is. The library has to
keep building natively for the tests, so the storage is a dune virtual
library with one implementation per target:

```
buf/            virtual library: buf.mli only (virtual_modules buf),
                default_implementation buf_native
buf/native/     Bigarray, as now
buf/js/         Float32Array / Int32Array directly, no Bigarray
```

```ocaml
(* buf.mli *)
type f32
type i32
val f32 : int -> f32                       (* zero-filled *)
val length_f : f32 -> int
val get : f32 -> int -> float
val set : f32 -> int -> float -> unit
val fill : f32 -> float -> unit
val blit_f : f32 -> f32 -> int -> unit     (* elements 0 .. len - 1 *)
val i32 : int -> i32
val length_i : i32 -> int
val geti : i32 -> int -> int32
val seti : i32 -> int -> int32 -> unit
val blit_i : i32 -> i32 -> int -> unit
```

- `caml2d` depends on `buf` only; the web executable links the JS
  implementation; the tests get the native one by default.
- `Vecarray` (`Float32Vec`, `Float32Vec2`, `BitVec`) and `Pair.Int32Pairs`
  use `Buf` instead of Bigarray. Nothing else changes.
- In JS the storage *is* the typed array, not a Bigarray with a view, so
  `expand` can't leave a stale view behind.
- In JS an Int32Array element is a JS integer, which is how js_of_ocaml
  represents `int32`, so `geti`/`seti` convert with `Obj.magic`.
- In the repo, each library needs a `public_name` under the `caml2d` package
  (`caml2d.buf`, `caml2d.buf.native`, `caml2d.buf.js`), because a public
  library can't depend on a private one. The experiment used private
  libraries, so that part is untested.

Tried in a scratch copy of `lib/`, with three JS implementations that differ
only in bounds checks:

- **`check` function:** `let get a i = check a##.length i; a[i]`;
- **check inside `get`:** `if i < 0 || i >= a##.length then oob () else a[i]`;
- **unchecked:** `a[i]`.

The full test suite ran natively and compiled to JS (`(modes js)`, in Node)
with each implementation, with the same results as the repo: all pass except
the two known failures. In each build, the benchmark's check against
`Collision.Resolver.apply` found a maximum difference of 0.

**The library's own `resolve`, unchanged,** on each storage. Headless
Chrome 156, 10,000 contacts, 550 calls:

| Storage | ns per contact | Allocated | Minor collections |
|---|---|---|---|
| Bigarray (current) | 119–122 | 318–322 MB | 318–322 |
| Typed arrays, `check` function | 70–76 | 318–319 MB | 318 |
| Typed arrays, check inside `get` | 44–52 | 134 MB | 134 |
| **Typed arrays, unchecked** | **30–31** | **7.8–8.3 MB** | **7–8** |
| *`rawt` hand-written loop, for reference* | *18–20* | *3.0–4.2 MB* | *3–4* |
| *none (setup and `detect` only)* | – | *2.2–2.6 MB* | *2* |

Times from three unprofiled runs. Memory from two profiled runs (one for the
check inside `get`). With unchecked typed arrays, the `Vec2` version of
`resolve` takes 48–55 ns (down from 124–135) but still allocates 1,840 MB,
and the packed version 131–135 ns and 270 MB.

- **The bounds check causes the boxing, not Bigarray.** With a separate
  `check` function, typed arrays allocate exactly as much as Bigarray: the
  same structure, `getx` → `get` → `check`, as Bigarray's `getx` →
  `caml_ba_get_1` → `ba.offset`/`ba.get`. Without the check, js_of_ocaml
  inlines `get` into `getx`, which becomes `return t[base]`, and V8 keeps the
  floats unboxed:

  ```js
  // check function
  function get(t3, i){check(t3.length, i); return t3[i];}
  function getx(t, i){var base = i * 2 | 0; return get(t, base);}
  // unchecked
  function getx(t, i){var base = i * 2 | 0; return t[base];}
  ```

- **A check inside `get` only half helps.** It removes the separate `check`
  call, but js_of_ocaml still doesn't inline `get`, so some boxing remains.
- **Unchecked, the library code is within 1.6× of the hand-written loop**
  (30 vs 19 ns), without changing `resolve`. The remaining gap is the
  `velx`/`vely` closures and the `update_add_i` calls.

**Decision:**

- Move `Vecarray` and `Pair` onto a virtual `Buf` library. The JS
  implementation stores typed arrays directly and is unchecked; the native
  one keeps Bigarray's bounds checks.
- Index bugs are caught by the tests, which run natively. In the browser an
  out-of-range read gives NaN and an out-of-range write is ignored, silently.
- Keep `resolve` written against `Vecarray`; a hand-written typed-array loop
  isn't worth it for the remaining 1.6×.
- Optionally run the tests under JS as well, with a second test stanza using
  `(modes js)` and the JS implementation.

### Packed vectors: where their allocation comes from

**Can packedvec2 stop allocating with `unsafe_get`?** No: the version
benchmarked already uses `Typed_array.unsafe_get`, and its accessors compile
to plain reads and writes of the scratch buffer, with no bounds checks:

```js
function x(t){f64[0] = t; return f32[0];}
function y(t){f64[0] = t; return f32[1];}
function v(x, y){f32[0] = x; f32[1] = y; return f64[0];}
```

(`web/packedvec2.ml` itself doesn't compile: no js_of_ocaml release (checked
5.0.0 to 6.4.1, and master) has `Typed_array.Float32Array`/`Float64Array`
modules; the only submodules are `Bigstring`, `String` and `Bytes`. The benchmark used a
rewrite with `new%js Typed_array.float32Array_fromBuffer` and `unsafe_get`,
which also fixes two bugs: the second `add` subtracts and should be `sub`,
and `dot` uses `y a *. y a` instead of `y a *. y b`.)

What matters is how vectors get in and out of the buffers. The packed
`resolve`, Chrome 156, 10,000 contacts:

| How vectors are loaded and stored | ns per contact | Allocated |
|---|---|---|
| through `Vecarray`, Bigarray storage | 206–216 | 724–735 MB |
| through `Vecarray`, unchecked typed-array storage | 131–135 | 268–272 MB |
| whole vectors through a Float64Array view (`packedt`) | 113–114 | 8.6–8.7 MB |

The setup and `detect` alone allocate 2.2–3.4 MB.

- **Through `Vecarray`,** each load assembles a vector from separate floats,
  `pget buf i = PV.v (V2.getx buf i) (V2.gety buf i)`, and each store takes
  it apart again: `padd_at buf i d = V2.set buf i (V2.getx buf i +. PV.x d)
  (V2.gety buf i +. PV.y d)`. Even on unchecked storage, that's many small
  calls with floats and packed values crossing them. Some of them aren't
  inlined, so some boxing remains.
- **Through a Float64Array view** of the same interleaved float32 buffer,
  each vector is one read (`p64[i]`) and one write. The calls to the packed
  operations remain, but almost nothing is boxed.
- **Even without allocation it's slow:** 114 ns, against 30 for the
  unchanged raw `resolve` on unchecked typed-array storage and 19 for the
  hand-written raw loop. Every `x`, `y` and `v` writes the shared 8-byte
  scratch buffer and reads it back. `f32`/`f64` are globals, so V8 has to
  keep those writes, and the components can't stay in registers. That cost
  is in packing itself; no way of reading the buffers removes it.

**Decision:** packed vectors stay rejected for arithmetic. To use them
without allocating, they would need whole-vector `get`/`set` over a
Float64Array view (a JS-only Vec2 storage), and they would only be worth it
where the number of loads and stores matters more than arithmetic.

### Pool

- `Pool.Make` hands out fixed-size elements up to a capacity. `acquire` doesn't
  zero reused elements (fresh ones come from `make`, which does).
- No longer used by `Linear`, which allocates its buffers once in `init`.
  Allocating a typed array per step was a measurable cost (and a leak
  in `Particles` until removed).
