module type Circles = sig
  type t
  
  val init: int -> t
  val set: t -> int -> position:Vec2.t -> prior_position:Vec2.t -> inv_mass:float -> radius:float -> unit
  val linear: t -> Positions.Linear.t
  (* force accumulator, one entry per circle: filled before each step,
     passed to [Positions.Linear.integrate], and zeroed by the caller *)
  val forces: t -> Positions.Linear.forces
  (* calls [f] for each circle with a radius greater than 0; a radius of 0
     marks an unused slot, which is skipped *)
  val iteri: (int -> x:float -> y:float -> radius:float -> unit) -> t -> unit

end


module type Collisions = sig
    type contacts
    
end

module Circles : Circles
  
