

module type Contacts = sig
    type t
    
    val create: int -> t
    val length: t -> int
    val depth: t -> int -> float
    val a: t -> i:int -> int
    val b: t -> i:int -> int
    val norm_x: t -> int -> float
    val norm_y: t -> int -> float
    
    (* find contacts from circle.t fill target with contact info return number of of contacts *)
    val detect: Rigid.Circles.t -> target:t -> unit
    
end
module V2 = Vecarray.Float32Vec2
module V1 = Vecarray.Float32Vec
module IntPairs = Pair.Int32Pairs

module PairwiseContacts : Contacts = struct
  type t = {mutable relations:IntPairs.t; mutable depths:V1.t; 
      mutable normals: V2.t; mutable count:int}


  let create n = 
    let relations = IntPairs.make n in 
    let depths = V1.make n in
    let normals = V2.make n in 
    {relations; depths; normals; count = 0}
  
  let capacity t = IntPairs.length t.relations

  let length t = t.count

  let a t ~i = IntPairs.get_a t.relations i

  let b t ~i = IntPairs.get_b t.relations i

  let norm_x t i = V2.getx t.normals i
  
  let norm_y t i = V2.gety t.normals i

  let depth t i = V1.get t.depths i

  let check_capacity t i = 
    let cap = (capacity t) in 
    if  cap <= i then 
      begin
        t.relations <- IntPairs.expand t.relations (cap * 2);
        t.depths <- V1.expand t.depths (cap * 2);
        t.normals <- V2.expand t.normals (cap * 2); 
      end 

  let detect c ~target = 
  
    let linear = Rigid.Circles.linear c in 
    let positions = Positions.Linear.positions linear in
    let size = V2.length positions in
    target.count <- 0;  
    for i = 0 to size - 1 do
      let radiusi = Rigid.Circles.radius c i in
      for j = i + 1 to size - 1 do
         
        let index = target.count in
        check_capacity target index;
        let dsquared = V2.distance_squared positions i j in
        let radiusj = Rigid.Circles.radius c j in
        let sum_r = radiusj +. radiusi in
        if (radiusj > 0.0) && (radiusi > 0.0) && (dsquared < (sum_r *. sum_r)) then
          begin 
            let d = Float.sqrt dsquared in
            IntPairs.set target.relations index ~a:i ~b:j;
            target.count <- index + 1;
            V1.set target.depths index (sum_r -. d);
            let dx = V2.getx positions j -. V2.getx positions i
              and dy = V2.gety positions j -. V2.gety positions i in
             if d > 0.0 then 
              V2.set target.normals index (dx /.d) (dy /. d)
            else 
              V2.set target.normals index 1. 0.
          
            
          end
      done
    done

end
