module type WORLD = sig
  val top_left : Vec2.t
  val bottom_right : Vec2.t
  val gravity : Vec2.t
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
  val iteri_positions : (int -> float -> float -> unit) -> t -> unit

  type points = Vecarray.Float32Vec2.t

  (* the current positions; the buffer is swapped by [integrate], so call
       this again after each step rather than keeping the result *)
  val positions : t -> points
end

module Make (W : WORLD) : S
