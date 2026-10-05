(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }
let run (x : owned @ local unique) = Eio.Cancel.protect (fun () -> x.n) [@nontail]
