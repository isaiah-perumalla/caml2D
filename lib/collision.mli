module type Contacts = sig
  type t

  val create : int -> t
  val length : t -> int
  val depth : t -> int -> float
  val a : t -> i:int -> int
  val b : t -> i:int -> int

  (* normal is from a to b *)
  val norm_x : t -> int -> float
  val norm_y : t -> int -> float

  (* find contacts from circle.t fill target with contact info return number of of contacts *)
  val detect : Rigid.Circles.t -> target:t -> unit
end

module PairwiseContacts : Contacts
