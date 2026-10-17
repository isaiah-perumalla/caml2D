module type BACKEND = sig
  type ctx
  type points
  
  val clear: ctx -> unit
  (* draws every point in [points] as a circle, labelled with its index *)
  val circles: ctx -> points -> radius:float -> unit
  val line: ctx -> x1:float -> y1:float -> x2:float -> y2:float -> unit

end



module type SOURCE = sig
  type t
  type points
  val positions : t -> points
end

module type S = sig
    type ctx
    type particles
    val render: ctx -> particles -> radius:float -> unit
end

module Make (B : BACKEND) (P : SOURCE with type points = B.points) : S with type ctx = B.ctx and type particles =  P.t
