open Caml2d
module Contacts = Collision.Contacts
module V2 = Vecarray.Float32Vec2

let dt = 1.

(* circles from (x, y, vx, vy, radius, inv_mass); the prior position is
   position - velocity * dt, so each circle starts with that velocity *)
let circles list =
  let n = List.length list in
  let c = Rigid.Circles.init n in
  List.iteri
    (fun i (x, y, vx, vy, radius, inv_mass) ->
      Rigid.Circles.set c i ~position:(Vec2.v x y)
        ~prior_position:(Vec2.v (x -. (vx *. dt)) (y -. (vy *. dt)))
        ~inv_mass ~radius)
    list;
  c

(* at rest: velocity 0 *)
let still (x, y, radius, inv_mass) = (x, y, 0., 0., radius, inv_mass)

(* detect then resolve with restitution [e]. Resolve moves the circles in
   place, so this snapshots positions and prior positions first and returns
   the contact count and each circle's change in position and in prior
   position *)
let run ?(e = 0.) c n =
  let contacts = Contacts.create 4 in
  let lin = Rigid.Circles.linear c in
  let snapshot buf = Array.init n (fun i -> (V2.getx buf i, V2.gety buf i)) in
  let pos0 = snapshot (Positions.Linear.positions lin)
  and prev0 = snapshot (Positions.Linear.prior_positions lin) in
  Collision.PairwiseContacts.circles c ~target:contacts;
  Collision.Resolver.apply contacts lin ~dt ~e;
  let change buf before =
    let d = V2.make n in
    Array.iteri
      (fun i (x, y) -> V2.set d i (V2.getx buf i -. x) (V2.gety buf i -. y))
      before;
    d
  in
  ( Contacts.length contacts,
    change (Positions.Linear.positions lin) pos0,
    change (Positions.Linear.prior_positions lin) prev0 )

let get buf i = (V2.getx buf i, V2.gety buf i)

let close (x, y) (x', y') =
  Float.abs (x -. x') < 1e-5 && Float.abs (y -. y') < 1e-5

(* velocity of circle i after resolve, from its position and prior position *)
let velocity c i =
  let lin = Rigid.Circles.linear c in
  let p = Positions.Linear.positions lin
  and q = Positions.Linear.prior_positions lin in
  ((V2.getx p i -. V2.getx q i) /. dt, (V2.gety p i -. V2.gety q i) /. dt)

(* --- detection --- *)

let () =
  (* one overlapping pair: a < b, depth = sum of radii - distance, and the
     normal points from a to b *)
  let c = circles [ still (0., 0., 5., 1.); still (6., 0., 5., 1.) ] in
  let contacts = Contacts.create 4 in
  Collision.PairwiseContacts.circles c ~target:contacts;
  assert (Contacts.length contacts = 1);
  assert (Contacts.a contacts ~i:0 = 0 && Contacts.b contacts ~i:0 = 1);
  assert (Contacts.depth contacts 0 = 4.);
  assert (Contacts.norm_x contacts 0 = 1. && Contacts.norm_y contacts 0 = 0.)

let () =
  (* more contacts than the initial capacity: the storage grows *)
  let c =
    circles
      [ still (0., 0., 5., 1.); still (1., 0., 5., 1.); still (2., 0., 5., 1.) ]
  in
  let contacts = Contacts.create 1 in
  Collision.PairwiseContacts.circles c ~target:contacts;
  assert (Contacts.length contacts = 3)

(* --- position corrections (circles at rest, so no bounce) --- *)

let () =
  (* equal masses: each moves half the overlap, away from the other.
     radius 5, 6 apart: depth 4, so -2 and +2 along the normal (1, 0) *)
  let n, pos, _ =
    run (circles [ still (0., 0., 5., 1.); still (6., 0., 5., 1.) ]) 2
  in
  assert (n = 1);
  assert (get pos 0 = (-2., 0.));
  assert (get pos 1 = (2., 0.))

let () =
  (* unequal masses: split by inverse mass. inv_mass 1 and 3, depth 4:
     i moves 1 back, j moves 3 forward *)
  let _, pos, _ =
    run (circles [ still (0., 0., 5., 1.); still (6., 0., 5., 3.) ]) 2
  in
  assert (get pos 0 = (-1., 0.));
  assert (get pos 1 = (3., 0.))

let () =
  (* an immovable circle doesn't move; the other takes the whole overlap *)
  let _, pos, _ =
    run (circles [ still (0., 0., 5., 0.); still (6., 0., 5., 1.) ]) 2
  in
  assert (get pos 0 = (0., 0.));
  assert (get pos 1 = (4., 0.))

let () =
  (* two immovable circles: still a contact, but nothing changes, no nan *)
  let n, pos, prev =
    run (circles [ still (0., 0., 5., 0.); still (6., 0., 5., 0.) ]) 2
  in
  assert (n = 1);
  assert (get pos 0 = (0., 0.) && get pos 1 = (0., 0.));
  assert (get prev 0 = (0., 0.) && get prev 1 = (0., 0.))

let () =
  (* the correction follows the normal, here along y *)
  let _, pos, _ =
    run (circles [ still (0., 0., 5., 1.); still (0., 6., 5., 1.) ]) 2
  in
  assert (get pos 0 = (0., -2.));
  assert (get pos 1 = (0., 2.))

let () =
  (* a circle in two contacts gets both corrections added together.
     A (0,0), B (6,0), C (6,6), radius 4: A-B and B-C overlap by 2,
     A-C don't touch. B is pushed +1 in x by A and -1 in y by C *)
  let n, pos, _ =
    run
      (circles
         [ still (0., 0., 4., 1.); still (6., 0., 4., 1.); still (6., 6., 4., 1.) ])
      3
  in
  assert (n = 2);
  assert (get pos 0 = (-1., 0.));
  assert (get pos 1 = (1., -1.));
  assert (get pos 2 = (0., 1.))

let () =
  (* circles that don't touch: no contact, no changes *)
  let n, pos, prev =
    run (circles [ still (0., 0., 3., 1.); still (10., 0., 3., 1.) ]) 2
  in
  assert (n = 0);
  assert (get pos 0 = (0., 0.) && get pos 1 = (0., 0.));
  assert (get prev 0 = (0., 0.) && get prev 1 = (0., 0.))

let () =
  (* once resolved, the overlap is gone: a second pass finds no contact *)
  let c = circles [ still (0., 0., 5., 1.); still (6., 0., 5., 1.) ] in
  let _, pos, _ = run c 2 in
  assert (get pos 0 = (-2., 0.) && get pos 1 = (2., 0.));
  let n, pos, _ = run c 2 in
  assert (n = 0);
  assert (get pos 0 = (0., 0.) && get pos 1 = (0., 0.))

(* --- bounce, for circles moving towards each other --- *)

(* i moving right at 1 into j at rest, equal masses, overlapping by 1 *)
let head_on () = circles [ (0., 0., 1., 0., 5., 1.); (9., 0., 0., 0., 5., 1.) ]

let () =
  (* e = 1 (elastic): equal masses swap velocities; the position correction
     (0.5 each) adds no velocity *)
  let c = head_on () in
  let _, pos, _ = run ~e:1. c 2 in
  assert (close (get pos 0) (-0.5, 0.));
  assert (close (get pos 1) (0.5, 0.));
  assert (close (velocity c 0) (0., 0.));
  assert (close (velocity c 1) (1., 0.))

let () =
  (* e = 0 (no bounce): the two move on together at the average velocity *)
  let c = head_on () in
  let _ = run ~e:0. c 2 in
  assert (close (velocity c 0) (0.5, 0.));
  assert (close (velocity c 1) (0.5, 0.))

let () =
  (* momentum is conserved whatever e is: the velocities still sum to 1 *)
  let c = head_on () in
  let _ = run ~e:0.5 c 2 in
  let vx0, _ = velocity c 0 and vx1, _ = velocity c 1 in
  assert (close (vx0 +. vx1, 0.) (1., 0.))

let () =
  (* moving into an immovable circle: the immovable one stays still, and the
     other comes back at e times its speed *)
  let c = circles [ (0., 0., 0., 0., 5., 0.); (9., 0., -1., 0., 5., 1.) ] in
  let _, pos, prev = run ~e:0.5 c 2 in
  assert (get pos 0 = (0., 0.) && get prev 0 = (0., 0.));
  assert (close (velocity c 0) (0., 0.));
  assert (close (velocity c 1) (0.5, 0.))

(* --- resting and separating overlaps: no bounce, and the position
   correction must not change the velocity --- *)

let () =
  (* at rest and overlapping: position and prior position move together, so
     neither circle gains velocity *)
  let c = circles [ still (0., 0., 5., 1.); still (6., 0., 5., 1.) ] in
  let _, pos, prev = run ~e:1. c 2 in
  assert (get prev 0 = get pos 0);
  assert (get prev 1 = get pos 1);
  assert (close (velocity c 0) (0., 0.));
  assert (close (velocity c 1) (0., 0.))

let () =
  (* already separating (i moving left, away from j): no bounce, and the
     velocities stay as they were *)
  let c = circles [ (0., 0., -1., 0., 5., 1.); (9., 0., 0., 0., 5., 1.) ] in
  let _ = run ~e:1. c 2 in
  assert (close (velocity c 0) (-1., 0.));
  assert (close (velocity c 1) (0., 0.))
