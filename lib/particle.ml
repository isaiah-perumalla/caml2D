type position = Position of Vec2.t
type prior_position = PriorPosition of Vec2.t
type force = Force of Vec2.t
type mass = Mass of float
type t = { position : position; prior_position : prior_position; mass : mass }

let create pos ppos (Mass m as mass) =
  (* written as a negated >= so that nan is rejected too *)
  if not (m >= 0.) then invalid_arg "Particle.create: mass must be non-negative";
  { position = pos; prior_position = ppos; mass }

let position p = p.position
let prior_position  p = p.prior_position

let inv_mass p =
  let (Mass m) = p.mass in
  if m = 0. then Mass 0. else Mass (1. /. m)

let mass p = p.mass
