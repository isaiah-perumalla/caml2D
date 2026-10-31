open Js_of_ocaml

type t = float

(* x and y as two float32s in the 8 bytes of one float64 *)
let buffer = new%js Typed_array.arrayBuffer 8
let f64 = new%js Typed_array.float64Array_fromBuffer buffer
let f32 = new%js Typed_array.float32Array_fromBuffer buffer

let x t =
  Typed_array.set f64 0 (Js.float t);
  Js.to_float (Typed_array.unsafe_get f32 0)

let y t =
  Typed_array.set f64 0 (Js.float t);
  Js.to_float (Typed_array.unsafe_get f32 1)

let v x y =
  Typed_array.set f32 0 (Js.float x);
  Typed_array.set f32 1 (Js.float y);
  Js.to_float (Typed_array.unsafe_get f64 0)

let zero = v 0. 0.

let add a b = 
  let x = (x a) +. (x b) and y = (y a) +. (y b) in
  v x y

let sub a b = 
  let x = (x a) -. (x b) and y = (y a) -. (y b) in
  v x y

let scale k a = v (k *. (x a) ) (k *. (y a) )

let dot a b = ((x a) *. (x b)) +. ((y a) *. (y b))

let magnitude t = sqrt (dot t t)

let distance a b = magnitude (sub a b)



(* let distance_squared a b =
  let dx = a.x -. b.x in
  let dy = a.y -. b.y in
  (dx *. dx) +. (dy *. dy)

let normalize a =
  let len = magnitude a in
  if len = 0. then zero else scale (1. /. len) a *) 
