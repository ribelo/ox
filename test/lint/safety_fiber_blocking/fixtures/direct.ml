(* ^safe-9ved: this deliberately unsafe program is compiled, never run. *)
let run () = Eio_main.run (fun _ -> Unix.sleepf 0.01)
