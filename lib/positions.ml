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
    let positions = PoolV2.acquire pool_v2 in
    let prev_positions = PoolV2.acquire pool_v2 in

    let inv_mass = PoolV1.acquire pool_v1 in

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
      let pos_ = PoolV2.acquire ps.pool_v2 in
      V2.scale_add ~target:pos_ ~a: !(ps.positions) ~scale_a: 2. ~b: !(ps.prev_positions) ~scale_b: (-1.);
      let a_ = PoolV2.acquire ps.pool_v2 in
      V2.scale_by_v ~target:a_ forces ps.inv_mass;
      V2.scale ~target:a_ a_ (dt *. dt);
      let x' = !(ps.prev_positions) in
      V2.add ~target:x' pos_ a_;
      ps.prev_positions := !(ps.positions);
      ps.positions := x';
      PoolV2.release ps.pool_v2 a_;
      PoolV2.release ps.pool_v2 pos_;

  
end

module Linear : Linear = L
