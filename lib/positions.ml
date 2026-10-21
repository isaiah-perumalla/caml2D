module type Linear = sig
  type t
  type forces = Vecarray.Float32Vec2.t

  val init : int -> t
  val get_prior_position : t -> int -> Vec2.t
  val get_position : t -> int -> Vec2.t
  val get_inv_mass : t -> int -> float

  val set :
    t ->
    int ->
    position:Vec2.t ->
    prior_position:Vec2.t ->
    inv_mass:float ->
    unit

  val iteri_positions : (int -> float -> float -> unit) -> t -> unit
  val integrate : t -> forces -> float -> unit
end

module V2 = Vecarray.Float32Vec2
module V1 = Vecarray.Float32Vec
module PoolV1 = Pool.Make (V1)
module PoolV2 = Pool.Make (V2)

module L = struct
  type forces = V2.t

  type t = {
    pool_v1 : PoolV1.t;
    pool_v2 : PoolV2.t;
    positions : V2.t ref;
    prev_positions : V2.t ref;
    inv_mass : V1.t;
  }

  let max_cap = 8
  
  let init n =
    let pool_v1 = PoolV1.create_pool ~size:n ~capacity:max_cap in
    let pool_v2 = PoolV2.create_pool ~size:n ~capacity:max_cap in
    let positions = V2.make n in
    let prev_positions = V2.make n in
    let inv_mass = V1.make n in

    {
      pool_v1;
      pool_v2;
      positions = ref positions;
      prev_positions = ref prev_positions;
      inv_mass;
    }

    let get_position ps i = 
      assert (i >= 0 && i < V2.length !(ps.positions));
      let posx = V2.getx !(ps.positions) i in
      let posy = V2.gety !(ps.positions) i in
      Vec2.v posx posy

    let get_prior_position ps i = 
      assert (i >= 0 && i < V2.length !(ps.prev_positions));
      let posx = V2.getx !(ps.prev_positions) i in
      let posy = V2.gety !(ps.prev_positions) i in
      Vec2.v posx posy

    let get_inv_mass ps i =
       assert (i >= 0 && i < V1.length ps.inv_mass);
       V1.get ps.inv_mass i

    let iteri_positions  f ps = V2.iteri f !(ps.positions) 

    let set ps i ~(position : Vec2.t) ~(prior_position : Vec2.t) ~inv_mass =
      assert (i >= 0 && i < V2.length !(ps.positions));
      V2.set !(ps.positions) i position.x position.y;
      V2.set !(ps.prev_positions) i prior_position.x prior_position.y;
      V1.set ps.inv_mass i inv_mass

    let integrate ps forces dt =
      (* verlet integration *)
      (* x' = 2x − prev + a·dt² *)
       (* verlet: x' = 2x − prev + f·inv_mass·dt², computed in place into prev *)
      let pos = !(ps.positions) and prev = !(ps.prev_positions) in
      (* prev := 2x -prev *)
      V2.scale_add ~target:prev ~a:pos ~scale_a: 2. ~b:prev ~scale_b: (-1.);
      (* prev := prev + (f x inv_mass) * dt²*)
      V2.acc_scale_by ~target:prev forces ps.inv_mass (dt *. dt);
    
      ps.prev_positions := pos;
      ps.positions := prev;
  
end

module Linear : Linear = L
