(* ^safe-9ved: ordinary opaque calls without a known wait are outside this rule. *)
let opaque fn () = Eio_main.run (fun env -> ignore (fn env))
let method_call service () = Eio_main.run (fun _ -> service#wait ())

let matched () =
  Eio_main.run (fun _ ->
    match Some Unix.sleep with Some f -> f 1 | None -> ())
