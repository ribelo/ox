(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
let run m (f : (unit -> int) @ local once) = let n = Eio.Mutex.use_rw ~protect:true m f in n + f ()
