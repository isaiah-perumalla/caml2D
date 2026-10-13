type  position = Position of Vec2.t 
type  velocity = Velocity of Vec2.t
type  force = Force of Vec2.t 
type  mass  = Mass of float


module Particle : sig
  type t 
  val position: t -> position
  val velocity: t -> velocity
  val mass: t -> mass
  val inv_mass: t -> mass
  val create : position -> velocity -> mass -> t
end


module Particles : sig
  type t 
  val init : int -> (int -> Particle.t) -> t
  val get : t -> int -> Particle.t
  val set : t -> int -> Particle.t -> unit
  val apply_force : t -> int -> force -> unit
  val integrate : t -> float -> unit
end
