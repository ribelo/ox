(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw (x : owned @ unique) =
 let fs = [fun () -> Ok (consume x)] in
 let _ = Ox.Concurrent.all ~sw fs in Ox.Concurrent.all ~sw fs
