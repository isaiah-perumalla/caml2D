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

module Int32Pairs : PAIRS with type elt = int
