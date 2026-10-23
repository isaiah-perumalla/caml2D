module type PAIRS = sig
  type t
  type elt

  val make : int -> t
  val length : t -> int
  val get_a : t -> int -> elt
  val get_b : t -> int -> elt
  val set : t -> int -> a:elt -> b:elt -> unit
end

module type SINGLES = sig
  type t
  type elt

  val make : int -> t
  val length : t -> int
  val get : t -> int -> elt
  val set : t -> int -> elt -> unit
end

type float32s =
  (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t

type int32s = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

module Int32_pairs : PAIRS with type elt = int = struct
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
end

module Float32_pairs : PAIRS with type elt = float = struct
  type t = float32s
  type elt = float

  let dim = 2
  let length t = Bigarray.Array1.dim t / dim

  let make size =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (size * dim)

  let get_a t i =
    let base = i * 2 in
    t.{base}

  let get_b t i =
    let base = i * 2 in
    t.{base + 1}

  let set t i ~a ~b =
    let base = i * 2 in
    t.{base} <- a;
    t.{base + 1} <- b
end

module Make_pair_to_single_assoc (K : PAIRS) (V : SINGLES) = struct
  type t = { keys : K.t; values : V.t; mutable next : int }

  let create n =
    let keys = K.make n in
    let values = V.make n in
    { keys; values; next = 0 }

  let add t ~a ~b value =
    if t.next < K.length t.keys then (
      let i = t.next in
      K.set t.keys i ~a ~b;
      V.set t.values i value;
      t.next <- i + 1;
      Some i)
    else None

  let count t = t.next

  let reset t = t.next <- 0
end
