
type t = { x : float; y : float }

val zero : t
val v : float -> float -> t
val add : t -> t -> t
val sub : t -> t -> t
val scale : float -> t -> t
val dot : t -> t -> float
val length : t -> float
val normalize : t -> t
val distance : t -> t -> float
val distance_squared : t -> t -> float

