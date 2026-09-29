(* ^ncaps-n6r0: an executable's entry ends the process with the Door's exit code; exit
   around an Ox_app call is the one raw exit the rules allow. *)
let () = exit (Ox_app.run_simple ~name:"demo" ~pp_err:(fun _ _ -> ()) (fun _ _ -> Ok ()))
