(* ^nonce-mjpe: authored public unique-ownership compiler control. *)
type owned = { value : int }
val consume : owned @ unique -> int
val handoff : 'e Ox.Scope.t -> owned @ unique -> (int, 'e) Ox.Scope.fork
