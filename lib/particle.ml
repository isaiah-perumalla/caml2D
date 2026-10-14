type position = Position of Vec2.t
type velocity = Velocity of Vec2.t
type force = Force of Vec2.t
type mass = Mass of float
type t = { position : position; velocity : velocity; mass : mass }

let create pos vel (Mass m as mass) =
  (* written as a negated >= so that nan is rejected too *)
  if not (m >= 0.) then invalid_arg "Particle.create: mass must be non-negative";
  { position = pos; velocity = vel; mass }

let position p = p.position
let velocity p = p.velocity

let inv_mass p =
  let (Mass m) = p.mass in
  if m = 0. then Mass 0. else Mass (1. /. m)

let mass p = p.mass
