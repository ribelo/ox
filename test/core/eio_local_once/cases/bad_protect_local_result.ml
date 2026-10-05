(* Native local-once provider controls. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }

let run () =
  let x = stack_ { n = 3 } in
  (Eio.Cancel.protect (fun () -> x) [@nontail])
