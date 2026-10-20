open Caml2d
module V2 = Vecarray.Float32Vec2
module Pool = Vecarray.Make (Vecarray.Float32Vec) (Vecarray.Float32Vec2)

let raises_assert f =
  match f () with exception Assert_failure _ -> true | _ -> false

let () =
  (* set writes x and y to the right slots, and only at that index *)
  let v = V2.make 3 in
  V2.set v 1 3. 4.;
  assert (V2.getx v 1 = 3.);
  assert (V2.gety v 1 = 4.);
  assert (V2.getx v 0 = 0. && V2.gety v 0 = 0.);
  assert (V2.getx v 2 = 0. && V2.gety v 2 = 0.)

let () =
  (* a released vector is reused, and comes back zeroed *)
  let pool = Pool.create_pool 3 in
  let v = Pool.acquire_2 pool in
  V2.set v 1 3. 4.;
  Pool.release_2 pool v;
  let w = Pool.acquire_2 pool in
  assert (w == v);
  V2.iteri (fun _ x y -> assert (x = 0. && y = 0.)) w

let () =
  (* releasing the same vector twice is caught *)
  let pool = Pool.create_pool 3 in
  let v = Pool.acquire_2 pool in
  Pool.release_2 pool v;
  assert (raises_assert (fun () -> Pool.release_2 pool v))

(* Pool *)

module P = Caml2d.Pool.Make (Vecarray.Float32Vec2)

let raises_failure f =
  match f () with exception Failure _ -> true | _ -> false

let () =
  (* the pool hands out at most max_cap elements; a released element is
     reused without counting against the cap *)
  let p = P.create_pool ~size:3 ~capacity:2 in
  let a = P.acquire p in
  let _b = P.acquire p in
  assert (raises_failure (fun () -> P.acquire p));
  P.release p a;
  assert (P.acquire p == a)
