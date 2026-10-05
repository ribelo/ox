(* ^nonce-mjpe: authored public unique-ownership compiler control. *)
type owned = { value : int }
val consume : owned @ unique -> int
val read : owned @ local unique -> int
val run : Ox.Rate_limiter.t -> owned @ local unique -> int
val drop : Ox.Rate_limiter.t -> owned @ local unique -> int option
val acquire : Eio.Switch.t -> owned @ local unique -> int
