open Particle

module type WORLD = sig
  val top_left : Vec2.t
  val bottom_right : Vec2.t
  val gravity : Vec2.t
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
  val iteri_positions : (int -> float -> float -> unit) -> t -> unit

  type points = Vecarray.Float32Vec2.t

  (* the current positions; the buffer is swapped by [integrate], so call
       this again after each step rather than keeping the result *)
  val positions : t -> points
end

module V2 = Vecarray.Float32Vec2
module V1 = Vecarray.Float32Vec
module Pool = Vecarray.Make (Vecarray.Float32Vec) (Vecarray.Float32Vec2)

module Make (W : WORLD) = struct
  module Config = W

  let () =
    if not (W.top_left.x < W.bottom_right.x && W.top_left.y < W.bottom_right.y)
    then
      invalid_arg "Particles.Make: top_left must be above-left of bottom_right"

  type buf = (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t

  type springs = {
    mutable count : int;
    mutable edges : int array; (* endpoints of spring i at 2i, 2i+1 *)
    mutable params : buf; (* stiffness at 2i, rest length at 2i+1 *)
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
    let new_params =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout new_capacity
    in
    Array.blit s.edges 0 new_edges 0 (slot_size * s.count);
    Bigarray.Array1.blit
      (Bigarray.Array1.sub s.params 0 (slot_size * s.count))
      (Bigarray.Array1.sub new_params 0 (slot_size * s.count));
    s.edges <- new_edges;
    s.params <- new_params

  let springs_connect s a b k rest_length =
    if s.count >= Array.length s.edges / 2 then grow_springs s;
    let idx = s.count in
    s.edges.(2 * idx) <- a;
    s.edges.((2 * idx) + 1) <- b;
    s.params.{2 * idx} <- k;
    s.params.{(2 * idx) + 1} <- rest_length;
    s.count <- s.count + 1

  let iter_springs f s =
    for i = 0 to s.count - 1 do
      let idx1 = s.edges.(2 * i) in
      let idx2 = s.edges.((2 * i) + 1) in
      let k = s.params.{2 * i} in
      let rest_length = s.params.{(2 * i) + 1} in
      f idx1 idx2 k rest_length
    done

  type t = {
    pool : Pool.t;
    positions : V2.t ref;
    prev_positions : V2.t ref;
    inv_mass : V1.t;
    forces : V2.t;
    springs : springs;
  }

  let write ps index p =
    let (Position pos) = Particle.position p in
    let (PriorPosition prev_pos) = Particle.prior_position p in
    let (Mass inv_mass) = Particle.inv_mass p in
    V2.set !(ps.positions) index pos.x pos.y;
    V2.set !(ps.prev_positions) index prev_pos.x prev_pos.y;
    V1.set ps.inv_mass index inv_mass

  let init n f =
    let pool = Pool.create_pool n in
    let positions = Pool.acquire_2 pool in
    let prev_positions = Pool.acquire_2 pool in

    let forces = Pool.acquire_2 pool in
    let inv_mass = Pool.acquire_1 pool in

    let springs = create_springs () in
    let ps =
      {
        pool;
        positions = ref positions;
        prev_positions = ref prev_positions;
        inv_mass;
        forces;
        springs;
      }
    in
    for i = 0 to n - 1 do
      write ps i (f i)
    done;
    ps

  let get ps i =
    assert (i >= 0 && i < V2.length !(ps.positions));
    let posx = V2.getx !(ps.positions) i in
    let posy = V2.gety !(ps.positions) i in
    let prevposx = V2.getx !(ps.prev_positions) i in
    let prevposy = V2.gety !(ps.prev_positions) i in
    let position = Vec2.v posx posy in
    let prev_position = Vec2.v prevposx prevposy in

    let inv_mass = V1.get ps.inv_mass i in
    let mass = if inv_mass = 0. then Mass 0. else Mass (1. /. inv_mass) in
    Particle.create (Position position) (PriorPosition prev_position) mass

  let set ps i particle =
    assert (i >= 0 && i < V2.length !(ps.positions));
    write ps i particle

  let add_force ps (Force f) = V2.update_add ps.forces f.x f.y

  (* unchecked: only called from the spring loop, whose indices were
     validated by [connect] *)
  let add_force_to_particle ps i fx fy =
    let x = V2.getx ps.forces i and y = V2.gety ps.forces i in
    V2.set ps.forces i (x +. fx) (y +. fy)

  let connect ps idx1 idx2 (Particle.Spring (k, rest_length)) =
    if
      idx1 < 0
      || idx1 >= V2.length !(ps.positions)
      || idx2 < 0
      || idx2 >= V2.length !(ps.positions)
    then invalid_arg "Particles.connect: index out of bounds";
    springs_connect ps.springs idx1 idx2 k rest_length

  let apply_spring_forces ps =
    iter_springs
      (fun a b k rest_length ->
        let posx = V2.getx !(ps.positions) a in
        let posy = V2.gety !(ps.positions) a in
        let posx' = V2.getx !(ps.positions) b in
        let posy' = V2.gety !(ps.positions) b in
        let dx = posx' -. posx in
        let dy = posy' -. posy in
        let distance_magnitude = sqrt ((dx *. dx) +. (dy *. dy)) in
        if distance_magnitude <> 0. then begin
          let spring_magnitude = k *. (distance_magnitude -. rest_length) in
          let fx = spring_magnitude *. (dx /. distance_magnitude) in
          let fy = spring_magnitude *. (dy /. distance_magnitude) in
          add_force_to_particle ps a fx fy;
          add_force_to_particle ps b (-.fx) (-.fy)
        end)
      ps.springs

  let integrate ps dt =
    apply_spring_forces ps;
    (* verlet integration *)
    (* x' = 2x − prev + a·dt² *)
    let size = V2.length !(ps.positions) in
    for i = 0 to size - 1 do
      let posx = V2.getx !(ps.positions) i in
      let posy = V2.gety !(ps.positions) i in
      let prev_posx = V2.getx !(ps.prev_positions) i in
      let prev_posy = V2.gety !(ps.prev_positions) i in
      let inv_mass = V1.get ps.inv_mass i in
      let g = if inv_mass = 0. then 0. else 1. in
      let ax = (V2.getx ps.forces i *. inv_mass) +. (g *. W.gravity.x) in
      let ay = (V2.gety ps.forces i *. inv_mass) +. (g *. W.gravity.y) in

      (* x' = 2x − prev + a·dt² *)
      let posx' = (2.0 *. posx) -. prev_posx +. (ax *. dt *. dt) in
      let posy' = (2.0 *. posy) -. prev_posy +. (ay *. dt *. dt) in
      V2.set !(ps.prev_positions) i posx' posy';

      (* boundary conditions *)
      (*should this be move to Bounds module ?*)
      if posx' < W.top_left.x || posx' > W.bottom_right.x then begin
        let dx = posx' -. posx in
        let adjusted_x =
          if posx' < W.top_left.x then W.top_left.x else W.bottom_right.x
        in
        V2.set !(ps.prev_positions) i adjusted_x
          (V2.gety !(ps.prev_positions) i);
        V2.set !(ps.positions) i (adjusted_x +. dx) (V2.gety !(ps.positions) i)
      end;

      if posy' < W.top_left.y || posy' > W.bottom_right.y then begin
        let dy = posy' -. posy in
        let adjusted_y =
          if posy' < W.top_left.y then W.top_left.y else W.bottom_right.y
        in
        V2.set !(ps.prev_positions) i
          (V2.getx !(ps.prev_positions) i)
          adjusted_y;
        V2.set !(ps.positions) i (V2.getx !(ps.positions) i) (adjusted_y +. dy)
      end
    done;

    let prev_positions = !(ps.positions) in
    ps.positions := !(ps.prev_positions);
    ps.prev_positions := prev_positions;
    V2.zero ps.forces

  let iteri_positions f t = V2.iteri f !(t.positions)

  type points = V2.t

  let positions t = !(t.positions)
end
