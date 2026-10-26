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

(* BitVec *)

module B = Vecarray.BitVec

(* the bits in [lo, hi] that are set, in order *)
let set_bits b lo hi =
  List.filter (B.isset b) (List.init (hi - lo + 1) (( + ) lo))

let () =
  (* a fresh bit vector has nothing set, including bits in its last, partly
     used word *)
  let b = B.make 40 in
  assert (set_bits b 0 39 = [])

let () =
  (* set and isset across the word boundary, including bit 31 (the sign bit
     of the first int32 word); neighbours stay clear *)
  let b = B.make 40 in
  List.iter (B.set b) [ 0; 31; 32; 39 ];
  assert (set_bits b 0 39 = [ 0; 31; 32; 39 ]);
  (* setting a bit twice leaves it set *)
  B.set b 31;
  assert (set_bits b 0 39 = [ 0; 31; 32; 39 ])

let () =
  (* clear turns off only its own bit, and clearing a clear bit is harmless *)
  let b = B.make 40 in
  List.iter (B.set b) [ 30; 31; 32 ];
  B.clear b 31;
  assert (set_bits b 0 39 = [ 30; 32 ]);
  B.clear b 31;
  B.clear b 5;
  assert (set_bits b 0 39 = [ 30; 32 ])

let () =
  (* expand to more bits keeps the set bits, and the new bits start clear *)
  let b = B.make 40 in
  List.iter (B.set b) [ 1; 33; 39 ];
  let g = B.expand b 100 in
  assert (set_bits g 0 99 = [ 1; 33; 39 ]);
  (* the new bits can be used *)
  B.set g 99;
  assert (B.isset g 99)

let () =
  (* expand to fewer bits keeps the set bits that still fit *)
  let b = B.make 100 in
  List.iter (B.set b) [ 2; 31; 70 ];
  let s = B.expand b 32 in
  assert (set_bits s 0 31 = [ 2; 31 ])

let () =
  (* last_set_index is -1 when nothing is set, including for an empty vector *)
  assert (B.last_set_index (B.make 100) = -1);
  assert (B.last_set_index (B.make 0) = -1)

let () =
  (* last_set_index follows the highest set bit as bits are set, across word
     boundaries and including bit 31, the sign bit of the first word *)
  let b = B.make 100 in
  B.set b 0;
  assert (B.last_set_index b = 0);
  B.set b 31;
  assert (B.last_set_index b = 31);
  B.set b 32;
  assert (B.last_set_index b = 32);
  B.set b 99;
  assert (B.last_set_index b = 99);
  (* setting a lower bit doesn't change it *)
  B.set b 50;
  assert (B.last_set_index b = 99)

let () =
  (* last_set_index drops when the highest bit is cleared, skipping any words
     that are now empty *)
  let b = B.make 100 in
  List.iter (B.set b) [ 3; 40; 99 ];
  B.clear b 99;
  assert (B.last_set_index b = 40);
  B.clear b 40;
  assert (B.last_set_index b = 3);
  B.clear b 3;
  assert (B.last_set_index b = -1)
