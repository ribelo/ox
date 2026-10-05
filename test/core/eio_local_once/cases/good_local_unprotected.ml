(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }
let run mutex (x : owned @ local unique) = Eio.Mutex.use_rw ~protect:false mutex (fun () -> x.n) [@nontail]
