module type SIZED = sig
  type t

  val make : int -> t
  val length : t -> int
  val zero : t -> unit
end

module Make (S : SIZED) : sig
  type t

  val create_pool : size:int -> capacity:int -> t
  val acquire : t -> S.t
  val release : t -> S.t -> unit
end = struct
  type t = {
    size : int;
    mutable alloc_count : int;
    mutable capacity : int;
    mutable free : S.t list;
  }

  let create_pool ~size ~capacity =
    (* invariant alloc_count <= capacity *)
    { size; capacity; alloc_count = 0; free = [] }

  let acquire p =
    match p.free with
    | [] ->
        if p.alloc_count >= p.capacity then
          failwith "Pool.acquire: capacity exceeded";
        p.alloc_count <- p.alloc_count + 1;
        S.make p.size
    | v :: rest ->
        p.free <- rest;
        S.zero v;
        v

  let release p v =
    assert (S.length v = p.size);
    assert (not (List.memq v p.free));
    p.free <- v :: p.free
end
