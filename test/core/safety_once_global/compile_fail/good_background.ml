(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw (x : owned @ unique) (y : owned @ unique) = Ox.Concurrent.with_background ~sw (fun () -> ignore (consume x); Ok ()) (fun () -> Ok (consume y))
