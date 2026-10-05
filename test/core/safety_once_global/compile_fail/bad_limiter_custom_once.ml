(* ^nonce-lrzq ^nonce-mjpe: local immediate callbacks do not weaken storage/repeat boundaries. *)
let bad ~sw ~clock (f @ once) =
 let config = Ox.Rate_limiter.Custom f in
 ignore (Ox.Rate_limiter.create ~sw ~clock config);
 Ox.Rate_limiter.create ~sw ~clock config
