(* ^nonce-mjpe: authored public unique-ownership compiler control. *)
type owned = { value : int }
val consume : owned @ unique -> int
val handoff : Eio.Switch.t -> owned -> unit
