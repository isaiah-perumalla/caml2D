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

module Make_pair_to_single_assoc (K : PAIRS) (V : SINGLES) : sig
  type t

  val create : int -> t
  val add : t -> a:K.elt -> b:K.elt -> V.elt -> int option
  val reset: t -> unit
  val count: t -> int
end

module Int32_pairs : PAIRS with type elt = int
module Float32_pairs : PAIRS with type elt = float

(* module Make_pair_to_pair_assoc(K:PAIRS) (V:PAIRS) : sig
  type t
  val create: int -> t
  val add: t -> int -> a:K.elt -> b:K.elt -> V.elt -> int
   
end *)
