module type PARAMS = sig
  val top_left : Vec2.t
  val bottom_right : Vec2.t
  val gravity : Vec2.t
end

module type ARENA = sig
  type t

  val create : max_circles:int -> t
  val add_area : t -> Area.t -> unit
  (* puts a circle in a free slot and returns its index, or [None] if every
     slot is in use; [radius] must be > 0 *)

  val add_circle :
    t ->
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

module Make (P : PARAMS) = struct
  module V2 = Vecarray.Float32Vec2
  module Params = P

  type t = {
    circles : Rigid.Circles.t;
    mutable areas : Area.t list;
    mutable index : int;
    forces : Positions.Linear.forces;
  }

  let create ~max_circles =
    let circles = Rigid.Circles.init max_circles in
    let forces = V2.make max_circles in
    { circles; areas = []; index = 0; forces }

  let add_area t a = t.areas <- a :: t.areas

  let add_circle t ~position ~prior_position ~inv_mass ~radius =
    let i = t.index in
    Rigid.Circles.set t.circles t.index ~position ~prior_position ~inv_mass
      ~radius;
    t.index <- i + 1;
    Some i

  let remove_circle t i = ()
  (* todo *)

  let step t dt =
    let p = Rigid.Circles.linear t.circles in
    V2.zero t.forces;
    List.iter
      (fun area -> Area.acc_forces ~area ~pos:p ~target:t.forces)
      t.areas;
    Positions.Linear.integrate p ~forces:t.forces dt

  let circles t = t.circles
end
