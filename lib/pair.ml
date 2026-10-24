module type PAIRS = sig
  type t
  type elt

  val make : int -> t
  val length : t -> int
  val get_a : t -> int -> elt
  val get_b : t -> int -> elt
  val set : t -> int -> a:elt -> b:elt -> unit
  val expand : t -> int -> t
end

type float32s =
  (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t

type int32s = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

module Int32Pairs : PAIRS with type elt = int = struct
  type t = int32s
  type elt = int

  let dim = 2
  let length t = Bigarray.Array1.dim t / 2

  let make size =
    Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout (size * dim)

  let get_a t i =
    let base = i * 2 in
    Int32.to_int t.{base}

  let get_b t i =
    let base = i * 2 in
    Int32.to_int t.{base + 1}

  let set t i ~a ~b =
    let base = i * 2 in
    t.{base} <- Int32.of_int a;
    t.{base + 1} <- Int32.of_int b

  let expand t new_size =
    let n = make new_size in
    (* copies the slots both buffers have, in one call *)
    let len = dim * Int.min (length t) new_size in
    Bigarray.Array1.blit
      (Bigarray.Array1.sub t 0 len)
      (Bigarray.Array1.sub n 0 len);
    n
end
