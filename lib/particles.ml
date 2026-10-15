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

  type buf = (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  type t = {
    positions : buf ref;
    prev_positions : buf ref;
    inv_mass : buf ;
    forces : buf;

  }

  let encode ps idx posx posy prevposx prevposy inv_mass =
    let base = idx * 2 in
    !(ps.positions).{base} <- posx;
    !(ps.positions).{base + 1} <- posy;
    !(ps.prev_positions).{base} <- prevposx;
    !(ps.prev_positions).{base + 1} <- prevposy;
    ps.inv_mass.{idx} <- inv_mass
    
    
  let write ps index p =
    let (Position pos) = Particle.position p in
    let (PriorPosition prev_pos) = Particle.prior_position p in
    let (Mass inv_mass) = Particle.inv_mass p in
    encode ps index pos.x pos.y prev_pos.x prev_pos.y inv_mass

  let init n f =
    let positions =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2) in
      let prev_positions =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2) in
    
    let forces =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (n * 2)
    in
    Bigarray.Array1.fill forces 0.;

    let inv_mass =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout n in
    Bigarray.Array1.fill inv_mass 0.;

    let ps = { positions = ref positions; prev_positions = ref prev_positions; 
                inv_mass = inv_mass; forces = forces } in
    for i = 0 to n - 1 do
      write ps i (f i)
    done;
    ps




let get ps index =
  if index < 0 || index >= Bigarray.Array1.dim !(ps.positions) / 2 then
    invalid_arg "Particles.get: index out of bounds";
  let idx = index * 2 in
  let posx = Bigarray.Array1.get !(ps.positions) idx in
  let posy = Bigarray.Array1.get !(ps.positions) (idx + 1) in
  let prevposx = Bigarray.Array1.get !(ps.prev_positions) idx in
  let prevposy = Bigarray.Array1.get !(ps.prev_positions) (idx + 1) in
  let position =
    Vec2.v
      posx
      posy
      
  in
  let prev_position =
    Vec2.v prevposx prevposy
  in
    
  let inv_mass = ps.inv_mass.{index} in
  let mass = if inv_mass = 0. then Mass 0. else Mass (1. /. inv_mass) in
  Particle.create (Position position) (PriorPosition prev_position) mass

let set ps index particle =
  if index < 0 || index >= Bigarray.Array1.dim !(ps.positions) / 2 then
    invalid_arg "Particles.set: index out of bounds";
  write ps index particle

let add_force ps (Force f) =
  let a = ps.forces in
  for i = 0 to Bigarray.Array1.dim a / 2 - 1 do
    let idx = i * 2 in
    a.{idx} <- a.{idx} +. f.x;
    a.{idx + 1} <- a.{idx + 1} +. f.y
  done
    

  let integrate ps dt =
    (* verlet integration *)
    let size = Bigarray.Array1.dim !(ps.positions) / 2 in
    for i = 0 to size - 1 do
      let idx = i * 2 in
      let  posx = !(ps.positions).{idx} in
      let  posy = !(ps.positions).{idx + 1} in
      let  prev_posx = !(ps.prev_positions).{idx} in
      let  prev_posy = !(ps.prev_positions).{idx + 1} in
      let  inv_mass = ps.inv_mass.{i} in
      let ax = ps.forces.{idx} *. inv_mass in
      let ay = ps.forces.{idx + 1} *. inv_mass in

      (* x' = 2x − prev + a·dt² *)
      let posx' = 2.0 *. posx -. prev_posx +. ax *. dt *. dt in
      let posy' = 2.0 *. posy -. prev_posy +. ay *. dt *. dt in
      !(ps.prev_positions).{idx} <- posx';
      !(ps.prev_positions).{idx + 1} <- posy'
    done;
    let prev_positions = !(ps.positions) in
    ps.positions := !(ps.prev_positions);
    ps.prev_positions := prev_positions;
    Bigarray.Array1.fill ps.forces 0.0



  let iteri_positions f t =
    let size = Bigarray.Array1.dim !(t.positions) / 2 in
    for i = 0 to size - 1 do
      let base = i * 2 in
      let posx =  !(t.positions).{base} in
      let posy =  !(t.positions).{base + 1} in
      f i posx posy
      
    done

end