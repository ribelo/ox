(* ^nlintc-du4v ^nlintc-kdcl: only an inline Program's tail receives Door evidence. *)
module Door = Ox_app

let work () = Ok ()
let report ppf error = Format.pp_print_string ppf error

let () =
  Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report (fun _ _ _ ->
      try work () with _ -> Error "terminal defect")

let () =
  Door.run_and_exit_with_args ~service_args:(Cmdliner.Term.const ()) ~name:"fixture"
    ~config:Door.Config.none ~pp_err:report (fun _ _ _ _ _ ->
      let () = () in
      if true then try work () with _ -> Error "terminal defect" else work ())

let program _ _ _ = try work () with _ -> Error "named deferred program"
let () = Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report program

let () =
  Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report (fun _ _ _ ->
      let discarded = try work () with _ -> Error "let rhs" in
      ignore discarded;
      work ())

let () =
  Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report (fun _ _ _ ->
      ignore (try work () with _ -> Error "discarded result");
      work ())

let boundary callback = callback ()

let () =
  Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report (fun _ _ _ ->
      boundary (fun () -> try work () with _ -> Error "unknown callback"))

let () =
  Door.run_and_exit ~name:"fixture" ~config:Door.Config.none ~pp_err:report (fun _ _ _ ->
      let result = ref (Ok ()) in
      (try result := work () with _ -> result := Error "stored result");
      !result)
