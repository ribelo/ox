(* ^nonce-lrzq ^nonce-mjpe: a local capture cannot enter a retained global callback. *)
type owned = { value : int }
let consume (x : owned @ local unique) = x.value
let reject (x : owned @ local unique) = Ox.Once.guard (fun () -> consume x)
