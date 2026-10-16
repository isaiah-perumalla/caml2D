type position = Position of Vec2.t
type prior_position = PriorPosition of Vec2.t
type force = Force of Vec2.t
type mass = Mass of float
type spring = Spring of float * float
type t

val position : t -> position
val prior_position : t -> prior_position
val mass : t -> mass
val inv_mass : t -> mass
val create : position -> prior_position -> mass -> t
