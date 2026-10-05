(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let read (x : owned @ local unique) = x.value
let handoff scope (x : owned @ local unique) = Ox.Scope.fork scope (fun () -> ignore (read x))
