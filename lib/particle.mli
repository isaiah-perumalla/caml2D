type position = Position of Vec2.t
type velocity = Velocity of Vec2.t
type force = Force of Vec2.t
type mass = Mass of float
type t

val position : t -> position
val velocity : t -> velocity
val mass : t -> mass
val inv_mass : t -> mass
val create : position -> velocity -> mass -> t
