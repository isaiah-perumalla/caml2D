open Particle

module type WORLD = sig 
    val top_left: Vec2.t
    val bottom_right: Vec2.t
    val gravity: Vec2.t
end

module type S = sig
    module Config : WORLD

    type t

    val init : int -> (int -> Particle.t) -> t
    val connect : t -> int -> int -> Particle.spring -> unit
    val get : t -> int -> Particle.t
    val set : t -> int -> Particle.t -> unit
    val add_force : t -> Particle.force -> unit
    val integrate : t -> float -> unit
    val iteri_positions : (int -> float -> float -> unit) -> t  -> unit
end

module Make (W : WORLD) = struct
  module Config = W

 let () =
    if not (W.top_left.x < W.bottom_right.x && W.top_left.y < W.bottom_right.y)
    then invalid_arg "Particles.Make: top_left must be above-left of bottom_right"

  type buf = (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  
  type springs = {
  mutable count : int;
  mutable edges : int array;   (* endpoints of spring i at 2i, 2i+1 *)
  mutable params : buf;       (* stiffness at 2i, rest length at 2i+1 *)
}

let create_springs () =
  let count = 0 in
  let edges = Array.make 16 0 in
  let params = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 16 in
  { count; edges; params }  

let grow_springs s =
  let new_capacity = max 8 (2 * Array.length s.edges) in
  let slot_size = 2 in
  let new_edges = Array.make new_capacity 0 in
  let new_params = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout new_capacity in
  Array.blit s.edges 0 new_edges 0  (slot_size * s.count);
  Bigarray.Array1.blit
  (Bigarray.Array1.sub s.params 0 (slot_size * s.count))
  (Bigarray.Array1.sub new_params 0 (slot_size * s.count));
  s.edges <- new_edges;
  s.params <- new_params  

let springs_connect s a b k rest_length =
  if s.count >= Array.length s.edges / 2 then
    grow_springs s;
  let idx = s.count in
  s.edges.(2 * idx) <- a;
  s.edges.(2 * idx + 1) <- b;
  s.params.{2 * idx} <- k;
  s.params.{2 * idx + 1} <- rest_length;
  s.count <- s.count + 1

  let iter_springs f s =
    for i = 0 to s.count - 1 do
      let idx1 = s.edges.(2 * i) in
      let idx2 = s.edges.(2 * i + 1) in
      let k = s.params.{2 * i} in
      let rest_length = s.params.{2 * i + 1} in
      f idx1 idx2 k rest_length;
    done


  type t = {
    positions : buf ref;
    prev_positions : buf ref;
    inv_mass : buf ;
    forces : buf;
    springs : springs;
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
    let springs = create_springs () in
    let ps = { positions = ref positions; prev_positions = ref prev_positions; 
                inv_mass = inv_mass; forces = forces; springs = springs } in
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
    
  let add_force_to_particle ps index fx fy =
    if index < 0 || index >= Bigarray.Array1.dim !(ps.positions) / 2 then
      invalid_arg "Particles.add_force_to_particle: index out of bounds";
    let idx = index * 2 in
    ps.forces.{idx} <- ps.forces.{idx} +. fx;
    ps.forces.{idx + 1} <- ps.forces.{idx + 1} +. fy


  let connect ps idx1 idx2 (Particle.Spring (k, rest_length)) =
    if idx1 < 0 || idx1 >= Bigarray.Array1.dim !(ps.positions) / 2 ||
       idx2 < 0 || idx2 >= Bigarray.Array1.dim !(ps.positions) / 2 then
      invalid_arg "Particles.connect: index out of bounds";
    springs_connect ps.springs idx1 idx2 k rest_length

  let apply_spring_forces ps =
    iter_springs (fun a b k rest_length ->
      let posx = !(ps.positions).{a * 2} in
      let posy = !(ps.positions).{a * 2 + 1} in
      let posx' = !(ps.positions).{b * 2} in
      let posy' = !(ps.positions).{b * 2 + 1} in
      let dx = posx' -. posx in
      let dy = posy' -. posy in
      let distance_magnitude = sqrt (dx *. dx +. dy *. dy) in
      if distance_magnitude <> 0. then begin
        let spring_magnitude = k *. (distance_magnitude -. rest_length) in
        let fx = spring_magnitude *. (dx /. distance_magnitude) in
        let fy = spring_magnitude *. (dy /. distance_magnitude) in
        add_force_to_particle ps a fx fy;
        add_force_to_particle ps b (-.fx) (-.fy)
      end) ps.springs
  
  let integrate ps dt =
    apply_spring_forces ps;
    (* verlet integration *)
    (* x' = 2x − prev + a·dt² *)
    let size = Bigarray.Array1.dim !(ps.positions) / 2 in
    for i = 0 to size - 1 do
      let idx = i * 2 in
      let  posx = !(ps.positions).{idx} in
      let  posy = !(ps.positions).{idx + 1} in
      let  prev_posx = !(ps.prev_positions).{idx} in
      let  prev_posy = !(ps.prev_positions).{idx + 1} in
      let  inv_mass = ps.inv_mass.{i} in
      let g = if inv_mass = 0. then 0. else 1. in
      let ax = (ps.forces.{idx} *. inv_mass) +. g *. W.gravity.x in
      let ay = (ps.forces.{idx + 1} *. inv_mass) +. g *. W.gravity.y in

      (* x' = 2x − prev + a·dt² *)
      let posx' = 2.0 *. posx -. prev_posx +. ax *. dt *. dt in
      let posy' = 2.0 *. posy -. prev_posy +. ay *. dt *. dt in
      !(ps.prev_positions).{idx} <- posx';
      !(ps.prev_positions).{idx + 1} <- posy'; 
      
      (* boundary conditions *)
      (*should this be move to Bounds module ?*)
      if posx' < W.top_left.x || posx' > W.bottom_right.x then
        begin
        let dx = (posx' -. posx)  in
        let adjusted_x = if posx' < W.top_left.x then W.top_left.x else W.bottom_right.x in
        !(ps.prev_positions).{idx} <- adjusted_x;
        !(ps.positions).{idx} <- adjusted_x +. dx;
        
        end;

      if posy' < W.top_left.y || posy' > W.bottom_right.y then begin
        let dy = (posy' -. posy)  in
        let adjusted_y = if posy' < W.top_left.y then W.top_left.y else W.bottom_right.y in
        !(ps.prev_positions).{idx + 1} <- adjusted_y;
        !(ps.positions).{idx + 1} <- adjusted_y +. dy
      end;    
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