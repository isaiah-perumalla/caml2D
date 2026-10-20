open Caml2d
module L = Positions.Linear
module V2 = Vecarray.Float32Vec2

(* values exact in float32, compared with [=] *)

let check ps i (px, py) (qx, qy) =
  assert (L.get_position ps i = Vec2.v px py);
  assert (L.get_prior_position ps i = Vec2.v qx qy)

let () =
  (* integrate moves every particle by velocity * dt, plus force / mass * dt^2 *)
  let ps = L.init 2 in
  L.set ps 0 ~position:(Vec2.v 1. 2.) ~prior_position:(Vec2.v 0. 0.) ~inv_mass:1.;
  L.set ps 1 ~position:(Vec2.v 0. 0.) ~prior_position:(Vec2.v 0. 0.) ~inv_mass:1.;
  let forces = V2.make 2 in
  V2.fill forces 1. 0.;
  L.integrate ps forces 1.0;
  (* particle 0 was already moving by (1, 2) per step *)
  check ps 0 (3., 4.) (1., 2.);
  check ps 1 (1., 0.) (0., 0.);

  (* no more forces: both keep moving at constant velocity *)
  V2.zero forces;
  L.integrate ps forces 1.0;
  check ps 0 (5., 6.) (3., 4.);
  check ps 1 (2., 0.) (1., 0.)

let () =
  (* inv_mass 0 is immovable: forces do not accelerate it *)
  let ps = L.init 1 in
  L.set ps 0 ~position:(Vec2.v 1. 2.) ~prior_position:(Vec2.v 1. 2.) ~inv_mass:0.;
  let forces = V2.make 1 in
  V2.fill forces 5. 5.;
  L.integrate ps forces 1.0;
  check ps 0 (1., 2.) (1., 2.)

let () =
  (* many steps reuse the pool's scratch buffers instead of exhausting it *)
  let ps = L.init 1 in
  let forces = V2.make 1 in
  for _ = 1 to 100 do
    L.integrate ps forces 1.0
  done
