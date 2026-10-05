(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff (x : owned @ unique) =
 let _f = Ox.Once.guard (fun () -> consume x) in consume x
