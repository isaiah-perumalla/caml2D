module type WORLD = sig 
    val top_left: Vec2.t
    val bottom_right: Vec2.t
    val gravity: Vec2.t
end

module type S = sig
    module Config : WORLD

    type t

    val init : int -> (int -> Particle.t) -> t
    val connect : t -> int -> int -> Particle.spring -> unit
    val get : t -> int -> Particle.t
    val set : t -> int -> Particle.t -> unit
    val add_force : t -> Particle.force -> unit
    val integrate : t -> float -> unit
    val iteri_positions : (int -> float -> float -> unit) -> t  -> unit
end

module Make (W: WORLD) : S