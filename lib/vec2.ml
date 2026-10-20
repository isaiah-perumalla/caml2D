type t = { x : float; y : float }

let zero = { x = 0.; y = 0. }
let v x y = { x; y }
let add a b = { x = a.x +. b.x; y = a.y +. b.y }
let sub a b = { x = a.x -. b.x; y = a.y -. b.y }
let scale k a = { x = k *. a.x; y = k *. a.y }
let dot a b = (a.x *. b.x) +. (a.y *. b.y)
let length a = sqrt (dot a a)
let distance a b = length (sub a b)

let distance_squared a b =
  let dx = a.x -. b.x in
  let dy = a.y -. b.y in
  (dx *. dx) +. (dy *. dy)

let normalize a =
  let len = length a in
  if len = 0. then zero else scale (1. /. len) a
