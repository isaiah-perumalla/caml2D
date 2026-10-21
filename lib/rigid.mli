module type Circles : sig
  type type
  
  val init: (int -> pos:Vec2.t -> prev_pos:Vec2.t -> inv_mass:float -> radius:float -> unit) -> int -> t

end


module type Collisions = sig
    type contacts
    
end
  
