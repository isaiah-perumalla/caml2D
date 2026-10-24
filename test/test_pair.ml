open Caml2d
module IP = Pair.Int32Pairs

let () =
  (* length counts pairs, not elements *)
  assert (IP.length (IP.make 3) = 3);
  assert (IP.length (IP.make 0) = 0)

let () =
  (* set then get round-trips at the first and last index, and each slot is
     independent of its neighbours *)
  let p = IP.make 3 in
  IP.set p 0 ~a:1 ~b:2;
  IP.set p 1 ~a:3 ~b:4;
  IP.set p 2 ~a:5 ~b:6;
  assert (IP.get_a p 0 = 1 && IP.get_b p 0 = 2);
  assert (IP.get_a p 1 = 3 && IP.get_b p 1 = 4);
  assert (IP.get_a p 2 = 5 && IP.get_b p 2 = 6);
  (* overwriting one slot leaves the others alone *)
  IP.set p 1 ~a:30 ~b:40;
  assert (IP.get_a p 0 = 1 && IP.get_b p 0 = 2);
  assert (IP.get_a p 1 = 30 && IP.get_b p 1 = 40);
  assert (IP.get_a p 2 = 5 && IP.get_b p 2 = 6)

let () =
  (* the int <-> int32 conversion keeps the sign and the full 32-bit range *)
  let p = IP.make 2 in
  IP.set p 0 ~a:(-1) ~b:(-123456);
  IP.set p 1 ~a:(Int32.to_int Int32.max_int) ~b:(Int32.to_int Int32.min_int);
  assert (IP.get_a p 0 = -1 && IP.get_b p 0 = -123456);
  assert (IP.get_a p 1 = Int32.to_int Int32.max_int);
  assert (IP.get_b p 1 = Int32.to_int Int32.min_int)
