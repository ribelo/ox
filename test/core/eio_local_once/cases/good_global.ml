(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
let run mutex f =
  let x = Eio.Cancel.protect f in
  let y = Eio.Mutex.use_rw ~protect:true mutex f in
  x + y + f ()
