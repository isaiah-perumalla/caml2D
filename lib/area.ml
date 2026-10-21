type params = {forces:Vec2.t; drag_const: float; gravity: Vec2.t }

type shape = 
  |Box of {top_left: Vec2.t; bottom_right: Vec2.t;}
  |Circular of  {center: Vec2.t; radius: float}

type t = {params:params; shape:shape}
module V2 = Vecarray.Float32Vec2

let acc_forces ~(area : t) ~(pos : Positions.Linear.t) ~(target : Positions.Linear.forces) =
  let g = area.params.gravity and f = area.params.forces in
  (* add gravitational force at i *)
  let add_g i =
    let inv_m = Positions.Linear.get_inv_mass pos i in
    let gx, gy = if inv_m = 0. then (0., 0.) else (g.x /. inv_m, g.y /. inv_m) in
    V2.set target i (V2.getx target i +. f.x +. gx) (V2.gety target i +. f.y +. gy)
  in
  match area.shape with
  | Box { top_left; bottom_right } ->
      (* bounds as local floats, so the per-body test is four comparisons *)
      let x0 = top_left.x and y0 = top_left.y
      and x1 = bottom_right.x and y1 = bottom_right.y in
      Positions.Linear.iteri_positions
        (fun i x y -> if x0 <= x && x <= x1 && y0 <= y && y <= y1 then add_g i)
        pos
  | Circular _ -> () (* TODO: not applied yet *)
