type params = {forces:Vec2.t; drag_const: float; gravity: Vec2.t }

type shape = 
  |Box of {top_left: Vec2.t; bottom_right: Vec2.t;}
  |Circular of  {center: Vec2.t; radius: float}

type t = {params:params; shape:shape}
module V2 = Vecarray.Float32Vec2

let box_contains (top:Vec2.t) (bottom:Vec2.t) x y=
  top.x <= x && x <= bottom.x && bottom.y >= y && y >= top.y

let test = function
  |Box ({top_left; bottom_right}) -> box_contains top_left bottom_right
  | _ -> fun _ _ -> false  

let acc_forces  ~(area:t) ~(pos: Positions.Linear.t)  ~(target:Positions.Linear.forces) =
    let tst = test area.shape in
    let g = area.params.gravity in
    let f = area.params.forces in
    Positions.Linear.iteri_positions (fun i x y -> 
          if tst x y then
              let inv_m = Positions.Linear.get_inv_mass pos i in
              let gx, gy = if inv_m = 0. then (0., 0.) else (g.x /. inv_m, g.y /. inv_m) in
              V2.set target i (V2.getx target i +. f.x +. gx) (V2.gety target i +. f.y +. gy) )
            pos


