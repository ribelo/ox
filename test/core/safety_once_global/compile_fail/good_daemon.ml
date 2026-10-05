(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff scope (x : owned @ unique) = Ox.Scope.fork_daemon scope (fun () -> ignore (consume x))
