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
  val expand : t -> int -> t (*create a new time with new size*)
  val set : t -> int -> float -> float -> unit
  val fill : t -> float -> float -> unit
  val distance_squared : t -> int -> int -> float
  val scale : target:t -> t -> float -> unit
  val add : target:t -> t -> t -> unit

  (* target := target + (t * (m1.t * float)) *)
  val acc_scale_by : target:t -> t -> M1.t -> float -> unit

  (* a*scale_a + b*scale_b  *)
  val scale_add :
    target:t -> a:t -> scale_a:float -> b:t -> scale_b:float -> unit

  val update_add_i : t -> int -> float -> float -> unit
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

module Float32Vec : MutableV1
module Float32Vec2 : MutableV2 with module M1 = Float32Vec
module BitVec : BITVEC

module Make (M1 : MutableV1) (M2 : MutableV2 with module M1 = M1) :
  S with module M1 = M1 and module M2 = M2
