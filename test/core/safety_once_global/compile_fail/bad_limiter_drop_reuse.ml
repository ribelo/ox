(* ^nonce-lrzq ^nonce-mjpe: local immediate callbacks do not weaken storage/repeat boundaries. *)
let bad limiter (f @ local once) =
 Ox.Rate_limiter.run_or_drop limiter f; Ox.Rate_limiter.run_or_drop limiter f
