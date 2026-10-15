module type BOUNDS = sig 
    val top_left: Vec2.t
    val bottom_right: Vec2.t
end

module type S = sig
    module B : BOUNDS

    type t

    val init : int -> (int -> Particle.t) -> t
    val get : t -> int -> Particle.t
    val set : t -> int -> Particle.t -> unit
    val add_force : t -> Particle.force -> unit
    val integrate : t -> float -> unit
    val iteri_positions : (int -> float -> float -> unit) -> t  -> unit
end

module Make (B: BOUNDS) : S