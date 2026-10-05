(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
let run (f : (unit -> int) @ local once) = (fun () -> Eio.Cancel.protect f)
