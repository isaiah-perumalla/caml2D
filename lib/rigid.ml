module type Circles = sig
  type t
  
  val init: int -> t
  val set: t -> int -> position:Vec2.t -> prior_position:Vec2.t -> inv_mass:float -> radius:float -> unit
  val linear: t -> Positions.Linear.t
  
  val iteri: (int -> x:float -> y:float -> radius:float -> unit) -> t -> unit 

end


module type Collisions = sig
    type contacts
    
end

module V1 = Vecarray.Float32Vec
module V2 = Vecarray.Float32Vec2

module C = struct
  type t = {radius:V1.t; linear:Positions.Linear.t; }

  let init n = 
    let l = Positions.Linear.init n in
    let radius = V1.make n in
    {radius; linear = l; }


  let linear t = t.linear
  
  let set t i ~position ~prior_position ~inv_mass ~radius =
    Positions.Linear.set t.linear i ~position ~prior_position ~inv_mass;
    V1.set t.radius i radius

  let iteri f t =
    let positions = Positions.Linear.positions t.linear in
    for i = 0 to (V1.length t.radius) -1 do
      let r = (V1.get t.radius i) in
      if 0.0 < r then  f i ~x:(V2.getx positions i ) ~y:(V2.gety positions i ) ~radius:r
    done

end


module Collisions = struct
  type contacts = Vec2.t
end

module Circles = C