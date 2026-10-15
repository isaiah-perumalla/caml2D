open Particle

module type BOUNDS = sig 
    val top_left: Vec2.t
    val bottom_right: Vec2.t
end

module type S = sig
    module B : BOUNDS

    type t

    val init : int -> (int -> Particle.t) -> t
    val get : t -> int -> Particle.t
    val set : t -> int -> Particle.t -> unit
    val add_force : t -> Particle.force -> unit
    val integrate : t -> float -> unit
    val iteri_positions : (int -> float -> float -> unit) -> t  -> unit
end

module Make (B : BOUNDS) = struct
  module B = B

 let () =
    if not (B.top_left.x < B.bottom_right.x && B.top_left.y < B.bottom_right.y)
    then invalid_arg "Particles.Make: top_left must be above-left of bottom_right"

  type t = {
    data : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
    forces : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t;
    count : int;
  }

  let encode ps idx posx posy velx vely inv_mass =
    Bigarray.Array1.set ps.data idx posx;
    Bigarray.Array1.set ps.data (idx + 1) posy;
    Bigarray.Array1.set ps.data (idx + 2) velx;
    Bigarray.Array1.set ps.data (idx + 3) vely;
    Bigarray.Array1.set ps.data (idx + 4) inv_mass

  let write ps index p =
    let (Position pos) = Particle.position p in
    let (Velocity vel) = Particle.velocity p in
    let (Mass inv_mass) = Particle.inv_mass p in
    encode ps (index * 5) pos.x pos.y vel.x vel.y inv_mass

  let init n f =
    let data =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 5)
    in
    let forces =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2)
    in
    Bigarray.Array1.fill forces 0.;
    let ps = { data; forces; count = n } in
    for i = 0 to n - 1 do
      write ps i (f i)
    done;
    ps


let encode ps idx posx posy velx vely inv_mass =
  Bigarray.Array1.set ps.data idx posx;
  Bigarray.Array1.set ps.data (idx + 1) posy;
  Bigarray.Array1.set ps.data (idx + 2) velx;
  Bigarray.Array1.set ps.data (idx + 3) vely;
  Bigarray.Array1.set ps.data (idx + 4) inv_mass

let write ps index p =
  let (Position pos) = Particle.position p in
  let (Velocity vel) = Particle.velocity p in
  let (Mass inv_mass) = Particle.inv_mass p in
  encode ps (index * 5) pos.x pos.y vel.x vel.y inv_mass

let init n f =
  let data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 5)
  in
  let forces =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2)
  in
  Bigarray.Array1.fill forces 0.;
  let ps = { data; forces; count = n } in
  for i = 0 to n - 1 do
    write ps i (f i)
  done;
  ps

let get ps index =
  if index < 0 || index >= ps.count then
    invalid_arg "Particles.get: index out of bounds";
  let idx = index * 5 in
  let position =
    Vec2.v
      (Bigarray.Array1.get ps.data idx)
      (Bigarray.Array1.get ps.data (idx + 1))
  in
  let velocity =
    Vec2.v
      (Bigarray.Array1.get ps.data (idx + 2))
      (Bigarray.Array1.get ps.data (idx + 3))
  in
  let inv_mass = Bigarray.Array1.get ps.data (idx + 4) in
  let mass = if inv_mass = 0. then Mass 0. else Mass (1. /. inv_mass) in
  Particle.create (Position position) (Velocity velocity) mass

let set ps index particle =
  if index < 0 || index >= ps.count then
    invalid_arg "Particles.set: index out of bounds";
  write ps index particle

let add_force ps (Force f) =
  let a = ps.forces in
  for i = 0 to ps.count - 1 do
    let idx = i * 2 in
    a.{idx} <- a.{idx} +. f.x;
    a.{idx + 1} <- a.{idx + 1} +. f.y
  done
    

  let integrate ps dt =
  for i = 0 to ps.count - 1 do
    let p = get ps i in
    let (Position pos) = Particle.position p in
    let (Velocity vel) = Particle.velocity p in
    let new_position = Vec2.add pos (Vec2.scale dt vel) in
    set ps i
      (Particle.create (Position new_position) (Particle.velocity p)
         (Particle.mass p))
  done

  let iteri_positions f t =
    for i = 0 to t.count - 1 do
      let base = i * 5 in
      let posx =  t.data.{base} in
      let posy =  t.data.{base + 1} in
      f i posx posy
      
    done

end