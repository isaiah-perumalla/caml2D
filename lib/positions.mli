module type Linear = sig
  type t
  type forces = Vecarray.Float32Vec2.t

  val init : int -> t
  val get_prior_position : t -> int -> Vec2.t
  val get_position : t -> int -> Vec2.t
  val get_inv_mass : t -> int -> float

  val set :
    t ->
    int ->
    position:Vec2.t ->
    prior_position:Vec2.t ->
    inv_mass:float ->
    unit

  val iteri_positions : (int -> float -> float -> unit) -> t -> unit
  val integrate : t -> forces -> dt:float -> unit
end
