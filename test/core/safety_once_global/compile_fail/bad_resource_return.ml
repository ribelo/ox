(* ^nonce-lrzq ^nonce-mjpe: local immediate callbacks do not weaken storage/repeat boundaries. *)
let bad ~sw () =
  let local_ r = { contents = 0 } in
  (Ox.Resource.use_in_scope ~sw (fun () -> r) (fun _ -> ()) [@nontail])
