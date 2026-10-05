(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
let run mutex =
  let n = Sys.opaque_identity 42 in
  let a = (Good_protect_local.run (stack_ { Good_protect_local.n }) [@nontail]) in
  let b = (Good_mutex_local.run mutex (stack_ { Good_mutex_local.n }) [@nontail]) in
  let c =
    (Good_local_unprotected.run mutex (stack_ { Good_local_unprotected.n }) [@nontail])
  in
  a + b + c
