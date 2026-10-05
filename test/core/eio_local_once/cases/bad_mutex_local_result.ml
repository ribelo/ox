(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }

let run m =
  let x = stack_ { n = 3 } in
  (Eio.Mutex.use_rw ~protect:true m (fun () -> x) [@nontail])
