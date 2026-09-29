open Ox
module Env = Env
module Status = Status
module Config = Config

type validation_error = Config.validation_error

type telemetry = {
  reporters : Ox_observability.Logger.Reporter.t list;
  span_ids : (unit -> string) option;
}

let status_query statuses () = List.map (fun status -> status ()) statuses

let serve ~sw () =
  Eio.Switch.check sw;
  Eio.Fiber.await_cancel ()

let stop_ids : Interrupt_id.t list ref Eio.Fiber.key = Eio.Fiber.create_key ()

let request_stop ~sw id =
  Option.iter (fun ids -> ids := id :: !ids) (Eio.Fiber.get stop_ids);
  Eio.Switch.fail sw (Eio.Cancel.Cancelled (Interrupt_id.stop id))

module type SERVICE = sig
  type t
  type config
  type deps
  type error

  val create : sw:Eio.Switch.t -> config -> deps -> (t, error) result
  val status : t -> Status.t
end

let render ~stop_ids ~interrupt_exit ~exit_code ~success stderr pp_err = function
  | Exit.Success value -> success value
  | Exit.Failure (Cause.Interrupt (Some id))
    when List.exists (Interrupt_id.equal id) !stop_ids ->
      interrupt_exit
  | Exit.Failure (Cause.Fail err) ->
      stderr (Format.asprintf "%a\n" pp_err err);
      exit_code err
  | Exit.Failure cause ->
      stderr (Format.asprintf "%a\n" (Cause.pp pp_err) cause);
      2

(* Runs after decoding and before the program's switch exists. A raise is a defect: it is
   rendered with Cause.pp, and [pp_err] renders any typed payload as it would for a program
   failure. [None] means the validator accepted the configuration. *)
let validation_failure ~validation_exit ~validate ~pp_err ~stderr env settings =
  match validate env settings with
  | Ok () -> None
  | Error errors ->
      Some
        (stderr (Config.render_validation_errors errors ^ "\n");
         validation_exit)
  | exception exn ->
      let cause = Cause.Die (exn, Printexc.get_raw_backtrace ()) in
      Some
        (stderr (Format.asprintf "%a\n" (Cause.pp pp_err) cause);
         2)

let run_for_test_with_args ?on_switch ?(commands = []) ?(config_commands = [])
    ?commands_with_env ?commands_with_env_code ?(bare = `Service) ?(usage_exit = 2)
    ?(exit_code = fun _ -> 1) ?(interrupt_exit = 130) ?(doc = "Run the service.")
    ?(validation_exit = 2) ?(log_level = Ox_observability.Logger.Info) ?journal_level
    ?(service_command = "run") ?(config_file = "config.toml") ?(missing = `Defaults)
    ?(validate = fun _ _ -> Ok ()) ?validate_source ?telemetry ?telemetry_result
    ~service_args ~env ~journal ~name ~config ~pp_err ~getenv ~read ~stderr ~stdout ~argv
    program =
  let open Cmdliner in
  let journal =
    match journal_level with
    | None -> journal
    | Some level -> Ox_observability.Logger.Reporter.at_least level journal
  in
  let initial_logger =
    Ox_observability.Logger.create ~service:name ~clock:env#clock
      ~mono_clock:env#mono_clock ~level:log_level ~reporter:journal ()
  in
  let door_env = { Env.base = env; logger = initial_logger } in
  let run_owned task =
    let requested = ref [] in
    let outcome =
      Scope.run (fun sw ->
          Eio.Fiber.with_binding stop_ids requested (fun () ->
              Option.iter (fun f -> f sw) on_switch;
              task sw))
    in
    render ~stop_ids:requested ~interrupt_exit:0 ~exit_code
      ~success:(fun () -> 0)
      stderr pp_err outcome
  in
  let run_owned_code task =
    let requested = ref [] in
    let outcome =
      Scope.run (fun sw ->
          Eio.Fiber.with_binding stop_ids requested (fun () ->
              Option.iter (fun f -> f sw) on_switch;
              Ok (task sw)))
    in
    render ~stop_ids:requested ~interrupt_exit ~exit_code ~success:Fun.id stderr pp_err
      outcome
  in
  let config_arg =
    Arg.(
      value
      & opt (some string) None
      & info [ "config" ] ~docv:"FILE" ~doc:"TOML configuration file.")
  in
  let prepare file =
    let source = Config.resolve_with ~file_name:config_file ~name ~config:file ~getenv in
    match Config.load_with ~missing ~spec:config ~getenv ~read ~source with
    | Error (`Config message) ->
        stderr (message ^ "\n");
        Error validation_exit
    | Ok settings -> (
        let failure =
          match
            validation_failure ~validation_exit ~validate ~pp_err ~stderr door_env
              settings
          with
          | Some _ as failure -> failure
          | None -> (
              match validate_source with
              | None -> None
              | Some validate ->
                  validation_failure ~validation_exit
                    ~validate:(fun env cfg -> validate env source cfg)
                    ~pp_err ~stderr door_env settings)
        in
        match failure with Some code -> Error code | None -> Ok (source, settings))
  in
  let execute file args () =
    match prepare file with
    | Error code -> code
    | Ok (source, settings) ->
        let requested = ref [] in
        let outcome =
          Scope.run (fun sw ->
              Eio.Fiber.with_binding stop_ids requested (fun () ->
                  (* ^napp-idii: the hook's reporters and ID generator build the
                           program's logger; the hook itself sees the validator's Env,
                           whose logger writes to the journal alone. Its resources are
                           acquired against this root switch, so they are released after
                           the program stops and before the Door returns. *)
                  let build (configured : telemetry) =
                    let logger =
                      Ox_observability.Logger.create ?span_ids:configured.span_ids
                        ~service:name ~clock:env#clock ~mono_clock:env#mono_clock
                        ~level:log_level
                        ~reporter:
                          (Ox_observability.Logger.Reporter.tee
                             (journal :: configured.reporters))
                        ()
                    in
                    { Env.base = env; logger }
                  in
                  (* ^napp-scz2: a hook that can fail returns its error as the program
                     would, so it is rendered through [pp_err] (exit 1) before the program
                     logger exists and the program is never entered. *)
                  let program_env =
                    match (telemetry, telemetry_result) with
                    | Some _, Some _ ->
                        invalid_arg
                          "Ox_app: give ?telemetry or ?telemetry_result, not both"
                    | None, None -> Ok door_env
                    | Some hook, None -> Ok (build (hook ~sw door_env settings))
                    | None, Some hook -> (
                        match hook ~sw door_env settings with
                        | Ok configured -> Ok (build configured)
                        | Error _ as error -> error)
                  in
                  match program_env with
                  | Error _ as error -> error
                  | Ok program_env ->
                      Option.iter (fun f -> f sw) on_switch;
                      program program_env source settings args sw))
        in
        render ~stop_ids:requested ~interrupt_exit:0 ~exit_code
          ~success:(fun () -> 0)
          stderr pp_err outcome
  in
  let run_term = Term.(const execute $ config_arg $ service_args) in
  let check file () =
    match prepare file with
    | Error code -> code
    | Ok (_source, settings) ->
        (* ^nnoschema-36cj: only the validated, redacted effective config. *)
        stdout (Yojson.Safe.to_string (config.yojson_of_t settings) ^ "\n");
        0
  in
  let check_term = Term.(const check $ config_arg) in
  (* ^napp-d5e4: the command that starts the program carries the service author's name,
     so a consumer can use `run` for a verb of its own. The group's default term is the
     same term, so a bare invocation starts the program whatever that command is called. *)
  let run_cmd = Cmd.v (Cmd.info service_command ~doc:"Start the program.") run_term in
  let check_cmd =
    Cmd.v
      (Cmd.info "check" ~doc:"Validate and print redacted effective configuration.")
      check_term
  in
  (* ^napp-wf22: the group is the Door's, so a consumer's `config init` is added to it
     here rather than built as a second group Cmdliner would refuse. *)
  let config_cmd =
    Cmd.group
      (Cmd.info "config" ~doc:"Inspect configuration.")
      (check_cmd :: config_commands)
  in
  let owned_commands =
    match commands_with_env with None -> [] | Some build -> build door_env run_owned
  in
  let owned_code_commands =
    match commands_with_env_code with
    | None -> []
    | Some build -> build door_env run_owned run_owned_code
  in
  let default = match bare with `Service -> Some run_term | `Help -> None in
  let cmd =
    Cmd.group ?default (Cmd.info name ~doc)
      ((run_cmd :: config_cmd :: commands) @ owned_commands @ owned_code_commands)
  in
  let out_buffer = Buffer.create 256 and err_buffer = Buffer.create 256 in
  let out_fmt = Format.formatter_of_buffer out_buffer
  and err_fmt = Format.formatter_of_buffer err_buffer in
  (* Cmdliner reports a group with no default as a usage error. For the bare-help
     contract, ask it to render its own top-level help instead. *)
  let eval_argv =
    if bare = `Help && Array.length argv = 1 then [| argv.(0); "--help" |] else argv
  in
  let parsed =
    Cmd.eval_value ~catch:false ~env:getenv ~argv:eval_argv ~help:out_fmt ~err:err_fmt cmd
  in
  Format.pp_print_flush out_fmt ();
  Format.pp_print_flush err_fmt ();
  if Buffer.length out_buffer > 0 then stdout (Buffer.contents out_buffer);
  if Buffer.length err_buffer > 0 then stderr (Buffer.contents err_buffer);
  match parsed with
  | Ok `Help | Ok `Version -> 0
  | Error _ -> usage_exit
  | Ok (`Ok f) -> f ()

let run_for_test ?on_switch ?commands ?config_commands ?doc ?validation_exit ?log_level
    ?journal_level ?service_command ?config_file ?missing ?validate ?validate_source
    ?telemetry ?telemetry_result ~env ~journal ~name ~config ~pp_err ~getenv ~read ~stderr
    ~stdout ~argv program =
  run_for_test_with_args ?on_switch ?commands ?config_commands ?doc ?validation_exit
    ?log_level ?journal_level ?service_command ?config_file ?missing ?validate
    ?validate_source ?telemetry ?telemetry_result ~service_args:(Cmdliner.Term.const ())
    ~env ~journal ~name ~config ~pp_err ~getenv ~read ~stderr ~stdout ~argv
    (fun env _source settings () sw -> program env settings sw)

let run_with_args ?commands ?config_commands ?commands_with_env ?commands_with_env_code
    ?bare ?usage_exit ?exit_code ?interrupt_exit ?doc ?validation_exit ?log_level
    ?journal_level ?service_command ?config_file ?missing ?read_file ?validate
    ?validate_source ?telemetry ?telemetry_result ~service_args ~name ~config ~pp_err
    program =
  Eio_main.run (fun env ->
      let signal = Atomic.make 0 in
      let signal_changed = Eio.Condition.create () in
      let on_signal signo =
        Atomic.set signal signo;
        Eio.Condition.broadcast signal_changed
      in
      (* Eio condition variables are domain-local, so this single-domain Door
       installs its handler with Sys.signal rather than Sys.Safe.signal, which
       requires a portable callback. *)
      let set_signal = (Sys.signal [@alert "-unsafe_multidomain"]) in
      let old_int = set_signal Sys.sigint (Sys.Signal_handle on_signal) in
      let old_term = set_signal Sys.sigterm (Sys.Signal_handle on_signal) in
      Fun.protect
        ~finally:(fun () ->
          ignore (set_signal Sys.sigint old_int);
          ignore (set_signal Sys.sigterm old_term))
        (fun () ->
          let on_switch sw =
            let sigint_id = Interrupt_id.create ()
            and sigterm_id = Interrupt_id.create () in
            Eio.Fiber.fork_daemon ~sw (fun () ->
                (* loop_no_mutex guards the atomic check / await_no_mutex boundary
             against a signal arriving just before the fiber suspends. *)
                let signo =
                  Eio.Condition.loop_no_mutex signal_changed (fun () ->
                      match Atomic.get signal with 0 -> None | signo -> Some signo)
                in
                request_stop ~sw (if signo = Sys.sigint then sigint_id else sigterm_id);
                `Stop_daemon)
          in
          (* ^napp-9x0s: nothing at a path is a read outcome, not a message, because the
             Door's own default path may be absent — Config.load decodes it as the empty
             document — while a file that is there and cannot be read is an error at
             either path. *)
          let read path =
            match read_file with
            | Some reader -> reader env path
            | None -> (
                try Ok (Eio.Path.load Eio.Path.(env#fs / path)) with
                | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) -> Error `Missing
                | Eio.Io _ as exn -> Error (`Unreadable (Printexc.to_string exn)))
          in
          run_for_test_with_args ?commands ?config_commands ?commands_with_env
            ?commands_with_env_code ?bare ?usage_exit ?exit_code ?interrupt_exit ?doc
            ?validation_exit ?log_level ?journal_level ?service_command ?config_file
            ?missing ?validate ?validate_source ?telemetry ?telemetry_result ~service_args
            ~on_switch ~env
            ~journal:(Ox_observability.Logger.Reporter.journal env#stderr)
            ~name ~config ~pp_err ~getenv:Sys.getenv_opt ~read
            ~stderr:(fun text -> Eio.Flow.copy_string text env#stderr)
            ~stdout:(fun text -> Eio.Flow.copy_string text env#stdout)
            ~argv:Sys.argv program))

let run ?commands ?config_commands ?doc ?validation_exit ?log_level ?journal_level
    ?service_command ?config_file ?missing ?read_file ?validate ?validate_source
    ?telemetry ?telemetry_result ~name ~config ~pp_err program =
  run_with_args ?commands ?config_commands ?doc ?validation_exit ?log_level ?journal_level
    ?service_command ?config_file ?missing ?read_file ?validate ?validate_source
    ?telemetry ?telemetry_result ~service_args:(Cmdliner.Term.const ()) ~name ~config
    ~pp_err (fun env _source settings () sw -> program env settings sw)
