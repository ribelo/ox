(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let run sw = Ox.Concurrent.for_each ~sw ~concurrency:2 [1;2] (fun x -> Ok x)
