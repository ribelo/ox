(* ^nonce-mjpe: authored public unique-ownership compiler control. *)
type owned = { value : int }
val consume : owned @ unique -> int
val run : Eio.Switch.t -> (int list, 'e) result
