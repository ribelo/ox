(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
let run (f : (unit -> int) @ local once) = let n = Eio.Cancel.protect f in n + f ()
