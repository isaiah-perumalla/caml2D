type  position = Position of Vec2.t 
type  velocity = Velocity of Vec2.t
type  force = Force of Vec2.t 
type  mass  = Mass of float

module Particle = struct
  type t = {
    position : position;
    velocity : velocity;
    inv_mass : mass;
  }

  let create  pos vel m = 
    let inv_mass = match m with Mass x -> if x = 0. then Mass 0. else Mass (1. /. x) in
    { position = pos; velocity = vel; inv_mass = inv_mass }
  let position p =  p.position
  let velocity  p =  p.velocity
  let inv_mass p =  p.inv_mass
  let mass p = if p.inv_mass = Mass 0. then Mass infinity else Mass (1. /. (match p.inv_mass with Mass x -> x))

end



module Particles = struct
  type t = {
    particles : ( float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
    forces : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
    count : int;
  }

  let init n f =
    let particles = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 5) in
    let forces = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2) in
    
    for i = 0 to n - 1 do
      let p = f i and idx = i * 3 in
      let (Position pos) = Particle.position p in
      let (Velocity vel) = Particle.velocity p in
      Bigarray.Array1.set particles idx pos.x;
      Bigarray.Array1.set particles (idx + 1) pos.y;
      Bigarray.Array1.set particles (idx + 2 ) vel.x;
      Bigarray.Array1.set particles (idx + 3) vel.y;
      Bigarray.Array1.set particles (idx + 4) (match p.inv_mass with Mass x -> x);

      Bigarray.Array1.set forces (i * 2) 0.;
      Bigarray.Array1.set forces (i * 2 + 1) 0.;
    done;
    { particles = particles; forces = forces; count = n }


  let get particles index =
    let idx = index * 5 in
    let position = Vec2.v (Bigarray.Array1.get particles.particles idx) (Bigarray.Array1.get particles.particles (idx + 1)) in
    let velocity = Vec2.v (Bigarray.Array1.get particles.particles (idx + 2)) (Bigarray.Array1.get particles.particles (idx + 3)) in
    let inv_mass = Bigarray.Array1.get particles.particles (idx + 4) in
    Particle.create (Position position) (Velocity velocity) (Mass inv_mass)

  
    let _encode_particle particles idx posx posy velx vely inv_mass =
        Bigarray.Array1.set particles.particles idx posx; 
        Bigarray.Array1.set particles.particles (idx + 1) posy;
        Bigarray.Array1.set particles.particles (idx + 2) velx;
        Bigarray.Array1.set particles.particles (idx + 3) vely;
        Bigarray.Array1.set particles.particles (idx + 4) inv_mass
  
    let set particles index particle =
      if index < 0 || index >= particles.count then
        invalid_arg "Particles.set: index out of bounds";

      let idx = index * 5 in
      let (Position pos) = Particle.position particle in
      let (Velocity vel) = Particle.velocity particle in
      _encode_particle particles idx pos.x pos.y vel.x vel.y (match particle.inv_mass with Mass x -> x)   

  let apply_force particles index force =
    let p = get particles index in
    let (Force f) = force in
    let (Velocity v) = Particle.velocity p in
    let (Mass inv_mass) = p.inv_mass in
    let acceleration = Vec2.scale inv_mass f in
    let new_velocity = Vec2.add v acceleration in
    let new_particle = { p with velocity = Velocity new_velocity } in
    set particles index new_particle

  let integrate particles dt = 
    for i = 0 to particles.count - 1 do
      let p = get particles i in
      let (Position pos) = Particle.position p in
      let (Velocity vel) = Particle.velocity p in
      let new_position = Vec2.add pos (Vec2.scale dt vel) in
      let new_particle = { p with position = Position new_position } in
      set particles i new_particle
    done
    
end