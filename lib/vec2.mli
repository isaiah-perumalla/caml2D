
type t
val zero : t
val v : float -> float -> t
val x : t -> float
val y : t -> float
val add : t -> t -> t
val sub : t -> t -> t
val scale : float -> t -> t
val dot : t -> t -> float
val normalize : t -> t
val magnitude: t -> float
val distance : t -> t -> float
val distance_squared : t -> t -> float
