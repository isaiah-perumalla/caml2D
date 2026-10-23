module type Collisions = sig
  type contacts

  val create : Rigid.Circles.t -> contacts
  val collisions : Rigid.Circles.t -> target:contacts -> unit
end
