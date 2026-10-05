(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let all sw (x : owned @ unique) = Ox.Concurrent.all ~sw [fun () -> Ok (consume x)]
let race sw (x : owned @ unique) = Ox.Concurrent.race ~sw [fun () -> Ok (consume x)]
let first sw (x : owned @ unique) = Ox.Concurrent.race_first ~sw [fun () -> Ok (consume x)]
