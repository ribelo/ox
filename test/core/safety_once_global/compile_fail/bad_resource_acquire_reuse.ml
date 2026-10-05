(* ^nonce-lrzq ^nonce-mjpe: local immediate callbacks do not weaken storage/repeat boundaries. *)
let bad ~sw (f @ local once) =
 Ox.Resource.use_in_scope ~sw f (fun _ -> ()); Ox.Resource.use_in_scope ~sw f (fun _ -> ())
