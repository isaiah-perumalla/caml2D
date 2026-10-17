module type BACKEND = sig
  type ctx
  
  val clear: ctx -> unit
  val circle: i:int -> ctx: ctx -> x:float -> y:float -> radius:float -> unit
  val line: ctx -> x1:float -> y1:float -> x2:float -> y2:float -> unit

end



module type SOURCE = sig
  type t
  val iteri_positions : (int -> float -> float -> unit) -> t -> unit
end

module type S = sig
    type ctx
    type particles
    val render: ctx -> particles -> radius:float -> unit
end

module Make (B : BACKEND) (P : SOURCE) : S with type ctx = B.ctx and type particles =  P.t
