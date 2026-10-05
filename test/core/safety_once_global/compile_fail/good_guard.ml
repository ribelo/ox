(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff (x : owned @ unique) = Ox.Once.guard (fun () -> consume x)
