(* ^nonce-lrzq ^nonce-mjpe: local immediate callbacks do not weaken storage/repeat boundaries. *)
let bad limiter =
  let local_ r = { contents = 0 } in
  (Ox.Rate_limiter.run limiter (fun () -> r) [@nontail])
