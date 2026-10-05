(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw (x : owned @ unique) (y : owned @ unique) = Ox.Concurrent.par ~sw (fun () -> Ok (consume x)) (fun () -> Ok (consume y))
