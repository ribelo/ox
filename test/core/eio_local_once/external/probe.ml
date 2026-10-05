(* No owning-scope package/interface overlay. ^nonce-lrzq ^nonce-mjpe *)
type owned = { n : int }
let protected (holder : owned @ local unique) =
  Eio.Cancel.protect (fun () -> holder.n) [@nontail]
let locked mutex (holder : owned @ local unique) =
  Eio.Mutex.use_rw ~protect:true mutex (fun () -> holder.n) [@nontail]
let () =
  Eio_main.run (fun _ ->
    let n = Sys.opaque_identity 42 in
    let first = protected (stack_ { n }) [@nontail] in
    let second = locked (Eio.Mutex.create ()) (stack_ { n }) [@nontail] in
    assert (first + second = 84))
