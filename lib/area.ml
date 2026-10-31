type params = { forces : Vec2.t; drag_const : float; gravity : Vec2.t }

type shape =
  | Box of { top_left : Vec2.t; bottom_right : Vec2.t }
  | Circular of { center : Vec2.t; radius : float }
  | Everywhere

type t = { params : params; shape : shape }

module V2 = Vecarray.Float32Vec2

let acc_forces ~(area : t) ~(pos : Positions.Linear.t)
    ~(target : Positions.Linear.forces) =
  let g = area.params.gravity and f = area.params.forces in
  let magnitude_g = Vec2.magnitude g in
  (* add gravitational force at i *)
  let add_g i ax ay =
    let inv_m = Positions.Linear.get_inv_mass pos i in
    let gx, gy =
      if inv_m = 0. then (0., 0.) else (ax /. inv_m, ay /. inv_m)
    in
    V2.set target i
      (V2.getx target i +. (Vec2.x f) +. gx)
      (V2.gety target i +. (Vec2.y f) +. gy)
  in
  match area.shape with
  | Box { top_left; bottom_right } ->
      (* bounds as local floats, so the per-body test is four comparisons *)
      let x0 = (Vec2.x top_left)
      and y0 = (Vec2.y top_left)
      and x1 = (Vec2.x bottom_right)
      and y1 = (Vec2.y bottom_right) in
      Positions.Linear.iteri_positions
        (fun i x y -> if x0 <= x && x <= x1 && y0 <= y && y <= y1 then add_g i (Vec2.x g) (Vec2.y g))
        pos
  | Circular {center; radius} -> 
    let rsquared = radius *. radius in  
    let cx = (Vec2.x center) and cy = (Vec2.y center) in
    let in_circle x y =
      rsquared > ((x -. cx) *. (x -. cx)) +. ((y -. cy) *. (y -. cy)) in
      

    Positions.Linear.iteri_positions
        (fun i x y -> if (in_circle x y) then 

          let gx = (cx -. x) and gy = (cy -. y) in
          let d = sqrt ((gx *. gx) +. (gy *. gy)) in
          if d > 0. then 
            let ax = (gx /. d) and ay = (gy /. d) in 
            add_g i (ax *. magnitude_g) (ay *. magnitude_g) )
        pos
  | Everywhere -> Positions.Linear.iteri_positions 
      (fun i x y -> add_g i (Vec2.x g) (Vec2.y g)) 
      pos
