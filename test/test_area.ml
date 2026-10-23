open Caml2d
module L = Positions.Linear
module V2 = Vecarray.Float32Vec2

(* values exact in float32, compared with [=] *)

(* a 10x10 box with its top-left corner at the origin; y grows downwards, as
   on the canvas *)
let box ?(forces = Vec2.zero) ?(gravity = Vec2.zero) () =
  Area.
    {
      shape = Box { top_left = Vec2.v 0. 0.; bottom_right = Vec2.v 10. 10. };
      params = { forces; drag_const = 0.; gravity };
    }

(* bodies at rest at the given positions, with the given inverse masses *)
let bodies list =
  let pos = L.init (List.length list) in
  List.iteri
    (fun i ((x, y), inv_mass) ->
      let p = Vec2.v x y in
      L.set pos i ~position:p ~prior_position:p ~inv_mass)
    list;
  pos

let force target i = (V2.getx target i, V2.gety target i)

let () =
  (* a body inside the box gets the force; bodies outside it, on any side,
     get nothing *)
  let pos =
    bodies
      [
        ((5., 5.), 1.);
        ((50., 5.), 1.);
        ((-5., 5.), 1.);
        ((5., 50.), 1.);
        ((5., -5.), 1.);
      ]
  in
  let target = V2.make 5 in
  Area.acc_forces ~area:(box ~forces:(Vec2.v 1. 2.) ()) ~pos ~target;
  assert (force target 0 = (1., 2.));
  for i = 1 to 4 do
    assert (force target i = (0., 0.))
  done

let () =
  (* the box includes its edges and corners *)
  let pos =
    bodies
      [ ((0., 0.), 1.); ((10., 10.), 1.); ((0., 10.), 1.); ((10., 5.), 1.) ]
  in
  let target = V2.make 4 in
  Area.acc_forces ~area:(box ~forces:(Vec2.v 1. 0.) ()) ~pos ~target;
  for i = 0 to 3 do
    assert (force target i = (1., 0.))
  done

let () =
  (* forces accumulate: what is already in [target] is kept *)
  let pos = bodies [ ((5., 5.), 1.) ] in
  let target = V2.make 1 in
  V2.set target 0 3. 4.;
  Area.acc_forces ~area:(box ~forces:(Vec2.v 1. 2.) ()) ~pos ~target;
  assert (force target 0 = (4., 6.))

let () =
  (* gravity is an acceleration, passed on as the force g / inv_mass: a body
     twice as heavy gets twice the force, so both accelerate the same *)
  let pos = bodies [ ((5., 5.), 1.); ((6., 6.), 0.5) ] in
  let target = V2.make 2 in
  Area.acc_forces ~area:(box ~gravity:(Vec2.v 0. 2.) ()) ~pos ~target;
  assert (force target 0 = (0., 2.));
  assert (force target 1 = (0., 4.))

let () =
  (* immovable bodies (inv_mass 0) get no gravity, rather than a division
     by zero *)
  let pos = bodies [ ((5., 5.), 0.) ] in
  let target = V2.make 1 in
  Area.acc_forces ~area:(box ~gravity:(Vec2.v 0. 2.) ()) ~pos ~target;
  assert (force target 0 = (0., 0.))
