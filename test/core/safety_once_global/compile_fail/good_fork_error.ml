(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff scope (x : owned @ unique) = Ox.Scope.fork_error scope (fun () -> Ok (consume x))
