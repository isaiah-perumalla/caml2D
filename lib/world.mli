
module type PARAMS = sig
    val top_left : Vec2.t
    val bottom_right : Vec2.t
    val gravity : Vec2.t
end


module type ARENA = sig
    type t 
    val create : max_circles:int -> t
    val add_area: t -> Area.t -> unit
     (* puts a circle in a free slot and returns its index, or [None] if every
     slot is in use; [radius] must be > 0 *)
    val add_circle : t ->
        position:Vec2.t ->
        prior_position:Vec2.t ->
        inv_mass:float ->
        radius:float ->
        int option

    (* frees the slot: radius 0 so it's skipped when drawing and colliding, and
     inv_mass 0 so areas and integration never move it *)
    val remove_circle : t -> int -> unit

    val step : t -> float -> unit
    val circles : t -> Rigid.Circles.t

end

module type MAKE = functor (P : PARAMS) -> ARENA
module Make : MAKE