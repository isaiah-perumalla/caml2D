module type BACKEND = sig
  type ctx
  
  val clear: ctx -> unit
  val circle: ctx -> x:float -> y:float -> radius:float -> unit
  val line: ctx -> x1:float -> y1:float -> x2:float -> y2:float -> unit

end

module type S = sig
    type ctx
    type particles
    val render: ctx -> particles -> radius:float -> unit
end

module type SOURCE = sig
  type t
  val iteri_positions : (int -> float -> float -> unit) -> t -> unit
end

module Make (B : BACKEND) (P : SOURCE) = struct
  type ctx = B.ctx
  type particles = P.t

  let render ctx ps ~radius =
    B.clear ctx;
    P.iteri_positions (fun _ x y -> B.circle ctx ~x ~y ~radius) ps
end

