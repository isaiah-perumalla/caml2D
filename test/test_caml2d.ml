open Caml2d

let () =
  let a = Vec2.v 3. 4. in
  assert (Vec2.length a = 5.);
  assert (Vec2.add a (Vec2.v 1. 1.) = Vec2.v 4. 5.);
  assert (Vec2.sub a a = Vec2.zero);
  assert (Vec2.scale 2. a = Vec2.v 6. 8.);
  assert (Vec2.dot a a = 25.)

(* Particles stores 32-bit floats, so these tests use values that are exact in
   float32 (small integers and powers of two) and compare with [=]. *)

open Particle

let particle ?(mass = 1.) (px, py) (vx, vy) =
  Particle.create
    (Position (Vec2.v px py))
    (PriorPosition (Vec2.v vx vy))
    (Mass mass)

(* big enough that no test particle reaches the walls *)
module W = Particles.Make (struct
  let top_left = Vec2.v (-1000.) (-1000.)
  let bottom_right = Vec2.v 1000. 1000.
  let gravity = Vec2.zero (* pixels per second^2 *)
end)

let raises_invalid_arg f =
  match f () with exception Invalid_argument _ -> true | _ -> false

(* a different particle for each index, so layout mistakes show up *)
let nth i =
  let k = float_of_int i in
  particle ~mass:(2. ** k) (k, k +. 10.) (k +. 20., k +. 30.)

let same_particle a b =
  Particle.position a = Particle.position b
  && Particle.prior_position a = Particle.prior_position b
  && Particle.mass a = Particle.mass b 
  

  let () =
  (* iter positions *)
  let ps = W.init 3 (fun i -> particle (W.Config.top_left.x /. 2.0, float_of_int i *. 3.) (0., 0.)) in
  let calls = ref 0 in
  W.iteri_positions (fun i x y ->
    assert (x = W.Config.top_left.x /. 2.);
    assert (y = float_of_int i *. 3.);
    incr calls) ps;
  
  assert (!calls = 3)

let () =
  (* Particle.create *)
  let p = particle ~mass:2. (1., 2.) (3., 4.) in
  assert (Particle.position p = Position (Vec2.v 1. 2.));
  assert (Particle.prior_position p = PriorPosition (Vec2.v 3. 4.));
  assert (Particle.mass p = Mass 2.);
  assert (Particle.inv_mass p = Mass 0.5);
  assert (Particle.inv_mass (particle ~mass:0. (0., 0.) (0., 0.)) = Mass 0.);
  assert (raises_invalid_arg (fun () -> particle ~mass:(-1.) (0., 0.) (0., 0.)));
  assert (raises_invalid_arg (fun () -> particle ~mass:nan (0., 0.) (0., 0.)))

let () =
  (* init then get returns every particle unchanged *)
  let n = 4 in
  let ps = W.init n nth in
  for i = 0 to n - 1 do
    assert (same_particle (W.get ps i) (nth i))
  done

let () =
  (* set changes only the particle at that index *)
  let ps = W.init 3 nth in
  let p = particle ~mass:4. (100., 200.) (-1., -2.) in
  W.set ps 1 p;
  assert (same_particle (W.get ps 0) (nth 0));
  assert (same_particle (W.get ps 1) p);
  assert (same_particle (W.get ps 2) (nth 2))

let () =
  (* out-of-range indices are rejected *)
  let ps = W.init 2 nth in
  assert (raises_invalid_arg (fun () -> W.get ps (-1)));
  assert (raises_invalid_arg (fun () -> W.get ps 2));
  assert (raises_invalid_arg (fun () -> W.set ps (-1) (nth 0)));
  assert (raises_invalid_arg (fun () -> W.set ps 2 (nth 0)))


let () =
  (* a particle with mass 0 is immovable: forces do not affect it *)
  let still = particle ~mass:0. (1., 2.) (0., 0.) in
  let ps = W.init 1 (fun _ -> still) in
  assert (same_particle (W.get ps 0) still)

let () =
  (* integrate moves every particle by velocity * dt *)
  let ps =
    W.init 2 (fun i ->
        if i = 0 then particle (1., 2.) (0., 0.) else particle (0., 0.) (0., 0.))
  in
  W.add_force ps (Force (Vec2.v 1. 0.));
  W.integrate ps 1.0;
  (* //first particle already moving *)
  assert (same_particle (W.get ps 0) (particle (3., 4.) (1., 2.)));
  assert (same_particle (W.get ps 1) (particle (1., 0.) (0., 0.)));

  (* no more forces applied everything should move a constnat velocity *)
  (* particle 0 should move at 2 units/step, particle 1 move 1 unit/step *)
  W.integrate ps 1.0;
  
  assert (same_particle (W.get ps 0) (particle (5., 6.) (3., 4.)));
  assert (same_particle (W.get ps 1) (particle (2., 0.) (1., 0.)))

(* a small box so particles move past the walls *)
module Box = Particles.Make (struct
  let top_left = Vec2.v 0. 0.
  let bottom_right = Vec2.v 10. 10.
  let gravity = Vec2.v 0. 0.
end)

let () =
  (* right wall: x = 9 moving +2 per step would reach 11, so it is clamped to
     10 and the prior is mirrored, sending it back inside on the next step *)
  let ps = Box.init 1 (fun _ -> particle (9., 5.) (7., 5.)) in
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (10., 5.) (12., 5.)));
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (8., 5.) (10., 5.)))

let () =
  (* floor only: y crosses the bottom wall while x stays inside *)
  let ps = Box.init 1 (fun _ -> particle (5., 9.) (5., 7.)) in
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (5., 10.) (5., 12.)))

let () =
  (* floor while moving sideways: y is clamped and mirrored, x keeps moving
     +1 per step, so the prior keeps the old x *)
  let ps = Box.init 1 (fun _ -> particle (5., 9.) (4., 7.)) in
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (6., 10.) (5., 12.)))

let () =
  (* bottom-right corner: both walls in the same step *)
  let ps = Box.init 1 (fun _ -> particle (9., 9.) (7., 7.)) in
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (10., 10.) (12., 12.)))

let () =
  (* top-left corner: left wall and ceiling *)
  let ps = Box.init 1 (fun _ -> particle (1., 1.) (3., 3.)) in
  Box.integrate ps 0.5;
  assert (same_particle (Box.get ps 0) (particle (0., 0.) (-2., -2.)))
