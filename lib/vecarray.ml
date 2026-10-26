module type BITVEC = sig
  type t

  val make : int -> t
  val expand : t -> int -> t
  val isset : t -> int -> bool
  val clear : t -> int -> unit
  val set : t -> int -> unit

  (* index of the highest set bit, or -1 if no bit is set *)
  val last_set_index : t -> int
end

module type V1 = sig
  type t

  val length : t -> int
  val get : t -> int -> float
  val iteri : (int -> float -> unit) -> t -> unit
end

module type MutableV1 = sig
  include V1

  val make : int -> t
  val expand : t -> int -> t
  val set : t -> int -> float -> unit
  val scale : target:t -> t -> float -> unit
  val add : target:t -> t -> t -> unit
  val zero : t -> unit
end

module type V2 = sig
  type t

  val length : t -> int
  val getx : t -> int -> float
  val gety : t -> int -> float
  val iteri : (int -> float -> float -> unit) -> t -> unit
end

module type MutableV2 = sig
  include V2
  module M1 : MutableV1

  val make : int -> t
  val expand : t -> int -> t
  val set : t -> int -> float -> float -> unit
  val fill : t -> float -> float -> unit
  val distance_squared : t -> int -> int -> float
  val scale : target:t -> t -> float -> unit
  val add : target:t -> t -> t -> unit
  val acc_scale_by : target:t -> t -> M1.t -> float -> unit

  val scale_add :
    target:t -> a:t -> scale_a:float -> b:t -> scale_b:float -> unit

  val update_add_i: t -> int -> float -> float -> unit
  val update_add : t -> float -> float -> unit

  (* val magnitude: target: M1.t -> t -> unit *)
  (* val normalize: target: t -> t -> unit *)
  val zero : t -> unit
end

module type S = sig
  module M1 : MutableV1
  module M2 : MutableV2 with module M1 = M1

  type t

  val create_pool : int -> t
  val acquire_1 : t -> M1.t
  val acquire_2 : t -> M2.t
  val release_1 : t -> M1.t -> unit (*recycle back to pool*)
  val release_2 : t -> M2.t -> unit (*recycle back to pool*)
end

type buffer = (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
type int32s = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

module BitVec : BITVEC = struct
  type t = int32s

  let make n =
    let size = (n + 31) / 32 in
    let bits = Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout size in

    Bigarray.Array1.fill bits 0l;
    bits

  let capacity t = 32 * Bigarray.Array1.dim t

  let expand t n =
    let bits = make n in
    let len = Int.min (Bigarray.Array1.dim t) (Bigarray.Array1.dim bits) in
    Bigarray.Array1.blit
      (Bigarray.Array1.sub t 0 len)
      (Bigarray.Array1.sub bits 0 len);
    bits

  let isset t i =
    let slot = i / 32 in
    let index = i mod 32 in
    let v = t.{slot} in
    let word = Int32.logand v (Int32.shift_left 1l index) in
    Int32.to_int word <> 0

  let clear t i =
    let slot = i / 32 in
    let index = i mod 32 in
    let v = t.{slot} in
    let v' = Int32.logand v (Int32.lognot (Int32.shift_left 1l index)) in
    t.{slot} <- v'

  let set t i =
    let slot = i / 32 in
    let index = i mod 32 in
    let v = t.{slot} in
    let v' = Int32.logor v (Int32.shift_left 1l index) in
    t.{slot} <- v'

  
  let rec first_zero_bit (word:int32) b =
    assert((Int32.to_int word) <> -1);
    let word' = Int32.logand word (Int32.shift_left 1l b) in
    if (Int32.to_int word') = 0 then b else first_zero_bit word (b + 1) 


  (* most significant bit in word , starting at bit b *)
  let rec msb (word:int32) b = 
      assert ((Int32.to_int word) <> 0);
      let word' = Int32.logand word (Int32.shift_left 1l b) in
      if  Int32.to_int word' <> 0 then b
      else msb word (b - 1)
  
  let last_set_index t =
    
    let rec word w =
      if w < 0 then -1
      else
        let v = t.{w} in
        if (Int32.to_int v) = 0 then word (w - 1)
        else
          (w * 32) + (msb v 31)
    in
    word (Bigarray.Array1.dim t - 1)
end

module Float32Vec : MutableV1 = struct
  type t = buffer

  let length v = Bigarray.Array1.dim v
  let get t i = t.{i}
  let set t i v = t.{i} <- v

  let add ~target a b =
    assert (length target = length a && length b = length a);
    for i = 0 to length a - 1 do
      target.{i} <- a.{i} +. b.{i}
    done

  let scale ~target a scale =
    assert (length target = length a);
    for i = 0 to length a - 1 do
      target.{i} <- a.{i} *. scale
    done

  let make size =
    let v = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout size in
    Bigarray.Array1.fill v 0.;
    v

  let expand t n =
    let v = make n in
    (* copies the slots both buffers have, in one call *)
    let len = Int.min (length t) n in
    Bigarray.Array1.blit
      (Bigarray.Array1.sub t 0 len)
      (Bigarray.Array1.sub v 0 len);
    v

  let zero t = Bigarray.Array1.fill t 0.

  let iteri f t =
    for i = 0 to length t - 1 do
      f i t.{i}
    done
end

module Float32Vec2 : MutableV2 with module M1 = Float32Vec = struct
  module M1 = Float32Vec

  type t = buffer

  let dim = 2
  let length v = Bigarray.Array1.dim v / dim

  let make size =
    let v =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (size * dim)
    in
    Bigarray.Array1.fill v 0.;
    v

  let getx t i =
    let base = i * dim in
    t.{base}

  let gety t i =
    let base = i * dim in
    t.{base + 1}

  let set t i x y =
    let base = i * dim in
    t.{base} <- x;
    t.{base + 1} <- y

  let expand t n =
    let v = make n in
    (* copies the slots both buffers have, in one call *)
    let len = dim * Int.min (length t) n in
    Bigarray.Array1.blit
      (Bigarray.Array1.sub t 0 len)
      (Bigarray.Array1.sub v 0 len);
    v

  let distance_squared t a b =
    let ax = getx t a in
    let ay = gety t a in

    let bx = getx t b in
    let by = gety t b in
    ((bx -. ax) *. (bx -. ax)) +. ((by -. ay) *. (by -. ay))

  let scale ~target t scale =
    assert (length target = length t);
    for i = 0 to length t - 1 do
      let base = i * dim in
      target.{base} <- scale *. t.{base};
      target.{base + 1} <- scale *. t.{base + 1}
    done

  let acc_scale_by ~target a scale k =
    assert (length target = M1.length scale);
    for i = 0 to length target - 1 do
      let s = k *. M1.get scale i in
      let base = i * dim in
      target.{base} <- target.{base} +. (s *. a.{base});
      target.{base + 1} <- target.{base + 1} +. (s *. a.{base + 1})
    done

  let scale_add ~target ~a ~scale_a ~b ~scale_b =
    assert (length target = length a);
    assert (length target = length b);
    for i = 0 to length target - 1 do
      let base = i * dim in
      target.{base} <- (scale_a *. a.{base}) +. (scale_b *. b.{base});
      target.{base + 1} <- (scale_a *. a.{base + 1}) +. (scale_b *. b.{base + 1})
    done

  let zero t = Bigarray.Array1.fill t 0.

  let fill t x y =
    for i = 0 to length t - 1 do
      let base = i * dim in
      t.{base} <- x;
      t.{base + 1} <- y
    done

  let update_add_i t i x y = 
    let base = i * dim in
      t.{base} <- t.{base} +. x;
      t.{base + 1} <- t.{base + 1} +. y
  
  let update_add t x y =
    for i = 0 to length t - 1 do
      let base = i * dim in
      t.{base} <- t.{base} +. x;
      t.{base + 1} <- t.{base + 1} +. y
    done

  let add ~target a b =
    assert (length target = length a && length b = length a);
    for i = 0 to length a - 1 do
      let base = i * dim in
      target.{base} <- a.{base} +. b.{base};
      target.{base + 1} <- a.{base + 1} +. b.{base + 1}
    done

  let iteri f t =
    for i = 0 to length t - 1 do
      let base = i * dim in
      f i t.{base} t.{base + 1}
    done
end

module Make (M1 : MutableV1) (M2 : MutableV2 with module M1 = M1) = struct
  module M1 = M1
  module M2 = M2

  type t = {
    size : int;
    mutable free_1 : M1.t list;
    mutable free_2 : M2.t list;
  }

  let create_pool size = { size; free_1 = []; free_2 = [] }

  let acquire_1 pool =
    match pool.free_1 with
    | [] -> M1.make pool.size
    | v :: rest ->
        pool.free_1 <- rest;
        M1.zero v;
        v

  let acquire_2 pool =
    match pool.free_2 with
    | [] -> M2.make pool.size
    | v :: rest ->
        pool.free_2 <- rest;
        M2.zero v;
        v

  let release_1 pool v =
    assert (M1.length v = pool.size);
    assert (not (List.memq v pool.free_1));
    pool.free_1 <- v :: pool.free_1

  let release_2 pool v =
    assert (M2.length v = pool.size);
    assert (not (List.memq v pool.free_2));
    pool.free_2 <- v :: pool.free_2
end
