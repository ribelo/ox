(* ^ncaps-0mvw ^nfloor-6n2e: the Door owns process exit. *)
let pp_err fmt = function `Failed -> Format.pp_print_string fmt "typed failure"

let () =
  Printexc.record_backtrace false;
  let command = Sys.argv.(1) in
  let program env () sw =
    Eio.Switch.on_release sw (fun () ->
        Eio.Flow.copy_string "released\n" env.Ox_app.Env.base#stdout);
    match List.rev (String.split_on_char '-' command) with
    | "fail" :: _ -> Error `Failed
    | "defect" :: _ -> failwith "entry defect"
    | "stop" :: _ ->
        Ox_app.request_stop ~sw (Ox.Interrupt_id.create ());
        Ox_app.serve ~sw ()
    | _ -> Ok ()
  in
  let code =
    if String.starts_with ~prefix:"return-" command then
      Ox_app.run ~service_command:command ~journal_level:Ox_observability.Logger.Error
        ~exit_code:(fun `Failed -> 23)
        ~name:"exit-fixture" ~config:Ox_app.Config.none ~pp_err program
    else if String.starts_with ~prefix:"args-" command then
      Ox_app.run_and_exit_with_args ~service_command:command
        ~journal_level:Ox_observability.Logger.Error
        ~exit_code:(fun `Failed -> 23)
        ~name:"exit-fixture" ~config:Ox_app.Config.none ~pp_err
        ~service_args:(Cmdliner.Term.const ())
        (fun env _source settings () sw -> program env settings sw)
    else
      Ox_app.run_and_exit ~service_command:command
        ~journal_level:Ox_observability.Logger.Error
        ~exit_code:(fun `Failed -> 23)
        ~name:"exit-fixture" ~config:Ox_app.Config.none ~pp_err program
  in
  Eio_main.run (fun env ->
      Eio.Flow.copy_string (Printf.sprintf "status=%d\n" code) env#stdout)
