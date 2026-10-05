(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let run sw (x : owned @ unique) = Ox.Concurrent.for_each ~sw ~concurrency:2 [1;2] (fun _ -> Ok (consume x))
