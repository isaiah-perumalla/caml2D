module Contacts : sig
  type t

  val create : int -> t
  val length : t -> int
  val depth : t -> int -> float
  val a : t -> i:int -> int
  val b : t -> i:int -> int

  (* normal is from a to b *)
  val norm_x : t -> int -> float
  val norm_y : t -> int -> float
  
end

module type DETECT = sig
  val circles : Rigid.Circles.t -> target:Contacts.t -> unit

end

module Resolver : sig

     (* moves overlapping bodies apart and applies the bounce, updating
     positions and prior positions in place; call after integrate *)
  val apply : Contacts.t -> Positions.Linear.t -> dt:float -> e:float -> unit
end
  


module PairwiseContacts : DETECT
