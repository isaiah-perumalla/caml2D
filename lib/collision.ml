
module V2 = Vecarray.Float32Vec2
module V1 = Vecarray.Float32Vec
module IntPairs = Pair.Int32Pairs

module Contacts  = struct
  type t = {
    mutable relations : IntPairs.t;
    mutable depths : V1.t;
    mutable normals : V2.t;
    mutable count : int;
    positions_corr : V2.t;
  }

  let create n =
    let relations = IntPairs.make n in
    let depths = V1.make n in
    let normals = V2.make n in
    let positions_corr = V2.make n in
    { relations; depths; normals; count = 0; positions_corr }

  let count t = t.count 

  let capacity t = IntPairs.length t.relations
  let length t = t.count
  let a t ~i = IntPairs.get_a t.relations i
  let b t ~i = IntPairs.get_b t.relations i
  let norm_x t i = V2.getx t.normals i
  let norm_y t i = V2.gety t.normals i
  let depth t i = V1.get t.depths i

  let check_capacity t i =
    let cap = capacity t in
    if cap <= i then begin
      t.relations <- IntPairs.expand t.relations (cap * 2);
      t.depths <- V1.expand t.depths (cap * 2);
      t.normals <- V2.expand t.normals (cap * 2)
    end

  let reset t =
    t.count <- 0;
    V2.zero t.positions_corr

end

module type DETECT = sig
  val circles : Rigid.Circles.t -> target:Contacts.t -> unit
end

module PairwiseContacts : DETECT = struct
  
  let circles c ~target =
    let linear = Rigid.Circles.linear c in
    let positions = Positions.Linear.positions linear in
    let size = V2.length positions in
    Contacts.reset target;

    for i = 0 to size - 1 do
      if Rigid.Circles.exists c i then begin
        let radiusi = Rigid.Circles.radius c i in
        for j = i + 1 to size - 1 do
          if Rigid.Circles.exists c j then begin
            let index = target.count in

            let dsquared = V2.distance_squared positions i j in
            let radiusj = Rigid.Circles.radius c j in
            let sum_r = radiusj +. radiusi in

            if radiusj > 0.0 && radiusi > 0.0 && dsquared < sum_r *. sum_r then begin
              Contacts.check_capacity target index;
              let d = Float.sqrt dsquared in
              IntPairs.set target.relations index ~a:i ~b:j;
              target.count <- index + 1;

              V1.set target.depths index (sum_r -. d);
              let dx = V2.getx positions j -. V2.getx positions i
              and dy = V2.gety positions j -. V2.gety positions i in
              let normx = dx /. d and normy = dy /. d in
              if d > 0.0 then V2.set target.normals index normx normy
              else V2.set target.normals index 1. 0.
            end
          end
        done
      end
    done
  
  end
  

module Resolver = struct
  let apply t linear ~dt ~e =
   
    let curr_positions = Positions.Linear.positions linear in
    let prev_positions = Positions.Linear.prior_positions linear in
    
    let e = 0.8 in 
    (* correction along the normal *)
    
    let inv_mass a = Positions.Linear.get_inv_mass linear a in
    
    let velx i = 
      let px = V2.getx (curr_positions) i and px' =  V2.getx (prev_positions) i in
      (px -. px') /. dt

    in
    
    let vely i = 
      let py = V2.gety (curr_positions) i and py' =  V2.gety (prev_positions) i in
      (py -. py') /. dt
    in

    for index = 0 to (Contacts.count t) - 1 do
      let i = IntPairs.get_a t.relations index
      and j = IntPairs.get_b t.relations index in
      let wi = inv_mass i and wj = inv_mass j in
       
      let w = wi +. wj in
      if w > 0. then begin
        (* two objs with infinite mass ignore*)
        let normx = V2.getx t.normals index in
        let normy = V2.gety t.normals index in
        
        let w' = 1. /. w in
        
        let d = V1.get t.depths index in
       
       
        (*collision depth*)
        
        let icorrx = -1. *. wi *. d *. w' *. normx in
        let icorry = -1. *. wi *. d *. w' *. normy in
        let jcorrx = wj *. d *. w' *. normx in
        let jcorry = wj *. d *. w' *. normy in
        let veljx = (velx j) and veljy = (vely j) in
        let velix = (velx i) and veliy = (vely i) in
        
        (* update after velocity is computed *)
        V2.update_add_i curr_positions i icorrx icorry;
        V2.update_add_i curr_positions j jcorrx jcorry;

       
        let rel_vel = ((veljx -. velix) *. normx) +. (( veljy -. veliy ) *. normy) in
        let impulse = (-1.) *. (1. +. e) *. rel_vel *. w' in
        if rel_vel < 0. then begin
          (* update velocities *)
          let velix' = velix -. impulse *. wi *. normx  and veliy' = veliy -.  impulse *. wi *. normy  in
          let veljx' = veljx +. impulse *. wj *. normx and veljy' = veljy +.  impulse *. wj *. normy in
          V2.update_add_i prev_positions i (-. (velix' -. velix) *. dt) (-. (veliy' -. veliy) *. dt);
          V2.update_add_i prev_positions j (-. (veljx' -. veljx) *. dt) (-. (veljy' -. veljy) *. dt);
          
        end;
        (* independent of rel_vel *)
        (* add corrections to prev-positon to keep velocity stable *)
        V2.update_add_i prev_positions i icorrx icorry;
        V2.update_add_i prev_positions j jcorrx jcorry;
      
      end
    done
end
