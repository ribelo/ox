(* ^nonce-mjpe: native unique record ownership, not a cast. *)
type owned = { value : int }
let consume (x : owned @ unique) = x.value
let read (x : owned @ local unique) = x.value
let run limiter (x : owned @ local unique) = Ox.Rate_limiter.run limiter (fun () -> read x) [@nontail]
let drop limiter (x : owned @ local unique) = Ox.Rate_limiter.run_or_drop limiter (fun () -> read x) [@nontail]
let acquire sw (x : owned @ local unique) = Ox.Resource.use_in_scope ~sw (fun () -> read x) ignore [@nontail]
