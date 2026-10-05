(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let handoff sw (x : owned @ unique) =
 Ox.Resource.use_in_scope ~sw (fun () -> 1) (fun _ -> ignore (consume x))
