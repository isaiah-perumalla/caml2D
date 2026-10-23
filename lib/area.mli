type params = { forces : Vec2.t; drag_const : float; gravity : Vec2.t }

(* y grows downwards, as on the canvas *)
type shape =
  | Box of { top_left : Vec2.t; bottom_right : Vec2.t }
  | Circular of { center : Vec2.t; radius : float } (* not applied yet *)
  | Everywhere

type t = { params : params; shape : shape }

(* adds this area's force to [target] for every body whose centre is inside
   it; what is already in [target] is kept *)
val acc_forces :
  area:t -> pos:Positions.Linear.t -> target:Positions.Linear.forces -> unit
