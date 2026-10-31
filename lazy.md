# `lazy` in the frame loop

How `web/circles.ml` creates its `requestAnimationFrame` callback once and
reuses it every frame, and why that needs `lazy`.

## What `lazy` does

`lazy e` is a **memoised computation with no arguments**. Creating it runs
nothing; it only records how to compute `e`. The first `Lazy.force` runs `e`,
stores the result in place, and returns it. Every later `Lazy.force` returns
the stored result without running `e` again.

```ocaml
let x = lazy (expensive ())   (* nothing runs yet: x is a suspended computation *)
Lazy.force x                  (* runs expensive (), stores the result, returns it *)
Lazy.force x                  (* returns the stored result; expensive () doesn't run again *)
```

## The frame loop, before and after

### Before: a new callback every frame

```ocaml
let rec loop acc last now =
  …
  request (loop !acc now)
and request f =
  let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
  ignore (Dom_html.window##requestAnimationFrame callback)
in
request (fun now -> loop 0. now now)
```

Each frame allocated:

- a closure for the partial application `loop !acc now`;
- a closure `fun now -> f (Js.to_float now)`;
- a new `Js.wrap_callback` wrapper around it.

`request` is a function, so the wrapping inside it ran again on every call.

### After: one callback, created once and reused

```ocaml
(* frame-loop state, kept across frames so nothing is allocated per frame *)
let acc = ref 0. and last = ref Float.nan in

let rec on_frame (now : Js.number_t) =
  let now = Js.to_float now in
  if Float.is_nan !last then last := now;      (* first frame: no elapsed time *)
  acc := !acc +. Float.min ((now -. !last) /. 1000.) max_dt;
  last := now;
  … (* physics steps, collisions, drawing *)
  ignore (Dom_html.window##requestAnimationFrame (Lazy.force callback))
and callback = lazy (Js.wrap_callback on_frame) in
ignore (Dom_html.window##requestAnimationFrame (Lazy.force callback))
```

- The frame state (`acc`, `last`) lives in refs created once, rather than in
  arguments rebuilt into a new closure each frame.
- `Js.wrap_callback on_frame` runs once, at the first `Lazy.force`. Every
  frame after that reuses the same wrapper.

## Why `lazy` is needed

The two definitions refer to each other:

- `on_frame` needs `callback`, to schedule the next frame;
- `callback` needs `on_frame`, because it is `on_frame` wrapped for JavaScript.

Definitions that refer to each other must be written with `let rec … and …`.
The obvious version doesn't compile:

```ocaml
let rec on_frame now = … requestAnimationFrame callback …
and callback = Js.wrap_callback on_frame
(* Error: This kind of expression is not allowed as right-hand side of `let rec' *)
```

In a `let rec`, every right-hand side must be something that can be built
**without running any code**: a function (`fun …`), a constructor, a record,
or `lazy …`. `Js.wrap_callback on_frame` is a function *call*. The compiler
can't know what `wrap_callback` does with `on_frame` while running; if it
called `on_frame` straight away, `on_frame` would read `callback` before
`callback` had a value. Rather than allow that, OCaml forbids calls there.

`lazy (…)` is allowed because creating it runs nothing. The call to
`Js.wrap_callback on_frame` is postponed until the first `Lazy.force`, on the
last line, after both definitions are complete.

The old version avoided the problem differently: `request` was a function,
which `let rec` allows, and the wrapping happened inside it. That is exactly
why it ran once per frame.

## What it costs

- **First `Lazy.force`:** runs `Js.wrap_callback on_frame` and stores the
  result.
- **Every later `Lazy.force`:** checks that the value is already computed and
  returns it. In the release JS this compiles to a comparison and a field
  read, with no allocation:

  ```js
  b = aP(an); a: if (a3 === b) b = an[1]; else { … }   // Lazy.force callback
  I.requestAnimationFrame(b);
  ```

What remains per frame is inside js_of_ocaml's wrapper itself
(`function(...a){…}`): the `...a` creates a small argument array on each call.
That's one tiny allocation per frame, down from three; removing it would mean
writing the callback in raw JavaScript.

## Alternatives

**A ref, filled in after `on_frame` is defined:**

```ocaml
let callback = ref None in
let on_frame now =
  …
  match !callback with
  | Some c -> ignore (Dom_html.window##requestAnimationFrame c)
  | None -> ()
in
callback := Some (Js.wrap_callback on_frame)
```

This works, but every frame pays for a `match` on a case (`None`) that can
never happen after start-up, and the code has to handle it anyway.

`lazy` says the same thing more directly: a value, computed once, that depends
on a function which depends on it.
