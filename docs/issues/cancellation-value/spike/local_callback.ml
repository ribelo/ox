type box = { n : int }
let good () = let b = stack_ { n = 41 } in Cancellation.with_ (fun _ -> b.n + 1) [@nontail]
let () = assert (good () = 42)
