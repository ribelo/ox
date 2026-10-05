(* ^nonce-mjpe: authored public unique-ownership compiler control. *)
type owned = { value : int }
val consume : owned @ unique -> int
val all : Eio.Switch.t -> owned @ unique -> (int list, 'e) result
val race : Eio.Switch.t -> owned @ unique -> (int, 'e Ox.Cause.t) result
val first : Eio.Switch.t -> owned @ unique -> (int, 'e) result
