(* typed arrays directly, no Bigarray. Unchecked: a bounds check stops
   js_of_ocaml inlining get/set, and the calls left behind make V8 box every
   float read (see design-choices.md, "Storage: typed arrays behind
   Vecarray") *)
open Js_of_ocaml
module TA = Typed_array

type f32 = TA.float32Array Js.t
type i32 = TA.int32Array Js.t

let f32 n : f32 = new%js TA.float32Array n (* zero-filled by JS *)
let length_f (a : f32) = a##.length
let get (a : f32) i = Js.to_float (TA.unsafe_get a i)
let set (a : f32) i v = TA.set a i (Js.float v)

let fill (a : f32) v =
  ignore (Js.Unsafe.meth_call a "fill" [| Js.Unsafe.inject (Js.float v) |])

let blit_f (src : f32) (dst : f32) len =
  dst##set_fromTypedArray (src##subarray 0 len) 0

let i32 n : i32 = new%js TA.int32Array n
let length_i (a : i32) = a##.length

(* both compile to plain reads and writes: geti is a[i] | 0 *)
let geti (a : i32) i = Int32.of_float (Js.to_float (TA.unsafe_get a i))
let seti (a : i32) i v = TA.set a i (Js.float (Int32.to_float v))

let blit_i (src : i32) (dst : i32) len =
  dst##set_fromTypedArray (src##subarray 0 len) 0
