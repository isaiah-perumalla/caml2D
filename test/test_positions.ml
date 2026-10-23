open Caml2d
module L = Positions.Linear
module V2 = Vecarray.Float32Vec2

(* values exact in float32, compared with [=] *)

(* fetches the buffers on every call: integrate swaps them, so a buffer
   taken before a step would be stale after it *)
let check ps i (px, py) (qx, qy) =
  let p = L.positions ps and q = L.prior_positions ps in
  assert (V2.getx p i = px && V2.gety p i = py);
  assert (V2.getx q i = qx && V2.gety q i = qy)

let () =
  (* integrate moves every particle by velocity * dt, plus force / mass * dt^2 *)
  let ps = L.init 2 in
  L.set ps 0 ~position:(Vec2.v 1. 2.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:1.;
  L.set ps 1 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:1.;
  let forces = V2.make 2 in
  V2.fill forces 1. 0.;
  L.integrate ps ~forces 1.0;
  (* particle 0 was already moving by (1, 2) per step *)
  check ps 0 (3., 4.) (1., 2.);
  check ps 1 (1., 0.) (0., 0.);

  (* no more forces: both keep moving at constant velocity *)
  V2.zero forces;
  L.integrate ps ~forces 1.0;
  check ps 0 (5., 6.) (3., 4.);
  check ps 1 (2., 0.) (1., 0.)

let () =
  (* inv_mass 0 is immovable: forces do not accelerate it *)
  let ps = L.init 1 in
  L.set ps 0 ~position:(Vec2.v 1. 2.) ~prior_position:(Vec2.v 1. 2.)
    ~inv_mass:0.;
  let forces = V2.make 1 in
  V2.fill forces 5. 5.;
  L.integrate ps ~forces 1.0;
  check ps 0 (1., 2.) (1., 2.)

let () =
  (* the same force moves a heavier body less *)
  let ps = L.init 2 in
  L.set ps 0 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:1.;
  L.set ps 1 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:0.5;
  let forces = V2.make 2 in
  V2.fill forces 0. 2.;
  L.integrate ps ~forces 1.0;
  check ps 0 (0., 2.) (0., 0.);
  check ps 1 (0., 1.) (0., 0.)

let () =
  (* an acceleration such as gravity is passed as the force a / inv_mass, so
     every movable body moves the same whatever its mass *)
  let ps = L.init 2 in
  L.set ps 0 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:1.;
  L.set ps 1 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:0.5;
  let forces = V2.make 2 in
  for i = 0 to 1 do
    V2.set forces i 0. (2. /. L.get_inv_mass ps i)
  done;
  L.integrate ps ~forces 1.0;
  check ps 0 (0., 2.) (0., 0.);
  check ps 1 (0., 2.) (0., 0.)

let () =
  (* a fractional dt scales the force term by dt^2:
     2·(1,1) − (0,0) + (4,8)·0.5·0.25 = (2.5, 3) *)
  let ps = L.init 1 in
  L.set ps 0 ~position:(Vec2.v 1. 1.) ~prior_position:(Vec2.v 0. 0.)
    ~inv_mass:0.5;
  let forces = V2.make 1 in
  V2.fill forces 4. 8.;
  L.integrate ps ~forces 0.5;
  check ps 0 (2.5, 3.) (1., 1.)

let () =
  (* many steps run without allocating or failing *)
  let ps = L.init 1 in
  let forces = V2.make 1 in
  for _ = 1 to 100 do
    L.integrate ps ~forces 1.0
  done
