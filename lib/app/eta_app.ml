open Eta
module Env = Env
module Status = Status
module Config = Config

type validation_error = Config.validation_error

type telemetry = {
  reporters : Eta_observability.Logger.Reporter.t list;
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

let render ~stop_ids stderr pp_err = function
  | Exit.Success () -> 0
  | Exit.Failure (Cause.Interrupt (Some id))
    when List.exists (Interrupt_id.equal id) !stop_ids ->
      0
  | Exit.Failure (Cause.Fail err) ->
      stderr (Format.asprintf "%a\n" pp_err err);
      1
  | Exit.Failure cause ->
      stderr (Format.asprintf "%a\n" (Cause.pp pp_err) cause);
      2

(* Runs after decoding and before the program's switch exists. A raise is a defect: it is
   rendered with Cause.pp, and [pp_err] renders any typed payload as it would for a program
   failure. [None] means the validator accepted the configuration. *)
let validation_failure ~validate ~pp_err ~stderr env settings =
  match validate env settings with
  | Ok () -> None
  | Error errors ->
      Some
        (stderr (Config.render_validation_errors errors ^ "\n");
         2)
  | exception exn ->
      let cause = Cause.Die (exn, Printexc.get_raw_backtrace ()) in
      Some
        (stderr (Format.asprintf "%a\n" (Cause.pp pp_err) cause);
         2)

let run_for_test ?on_switch ?(commands = []) ?(config_commands = [])
    ?(service_command = "run") ?(validate = fun _ _ -> Ok ()) ?telemetry ~env ~journal
    ~name ~config ~pp_err ~getenv ~read ~stderr ~stdout ~argv program =
  let open Cmdliner in
  let config_arg =
    Arg.(
      value
      & opt (some string) None
      & info [ "config" ] ~docv:"FILE" ~doc:"TOML configuration file.")
  in
  let execute check file () =
    let source = Config.resolve ~name ~config:file ~getenv in
    match Config.load ~spec:config ~getenv ~read ~source with
    | Error (`Config message) ->
        stderr (message ^ "\n");
        2
    | Ok settings -> (
        let logger =
          Eta_observability.Logger.create ~service:name ~clock:env#clock
            ~mono_clock:env#mono_clock ~reporter:journal ()
        in
        let door_env = { Env.base = env; logger } in
        match validation_failure ~validate ~pp_err ~stderr door_env settings with
        | Some code -> code
        | None ->
            if check then (
              (* ^nnoschema-36cj: the effective config after environment overrides,
                 rendered by the type's derived encoder; secrets are Redact.t and
                 encode as "<redacted>". *)
              stdout (Yojson.Safe.to_string (config.yojson_of_t settings) ^ "\n");
              0)
            else
              let requested = ref [] in
              let outcome =
                Scope.run (fun sw ->
                    Eio.Fiber.with_binding stop_ids requested (fun () ->
                        (* ^napp-idii: the hook's reporters and ID generator build the
                           program's logger; the hook itself sees the validator's Env,
                           whose logger writes to the journal alone. Its resources are
                           acquired against this root switch, so they are released after
                           the program stops and before the Door returns. *)
                        let program_env, program =
                          match telemetry with
                          | None -> (door_env, program)
                          | Some hook ->
                              let configured = hook ~sw door_env settings in
                              let logger =
                                Eta_observability.Logger.create
                                  ?span_ids:configured.span_ids ~service:name
                                  ~clock:env#clock ~mono_clock:env#mono_clock
                                  ~reporter:
                                    (Eta_observability.Logger.Reporter.tee
                                       (journal :: configured.reporters))
                                  ()
                              in
                              ({ Env.base = env; logger }, program)
                        in
                        Option.iter (fun f -> f sw) on_switch;
                        program program_env settings sw))
              in
              render ~stop_ids:requested stderr pp_err outcome)
  in
  let run_term = Term.(const (execute false) $ config_arg) in
  let check_term = Term.(const (execute true) $ config_arg) in
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
  let cmd =
    Cmd.group ~default:run_term
      (Cmd.info name ~doc:"Run the service.")
      (run_cmd :: config_cmd :: commands)
  in
  let out_buffer = Buffer.create 256 and err_buffer = Buffer.create 256 in
  let out_fmt = Format.formatter_of_buffer out_buffer
  and err_fmt = Format.formatter_of_buffer err_buffer in
  let parsed =
    Cmd.eval_value ~catch:false ~env:getenv ~argv ~help:out_fmt ~err:err_fmt cmd
  in
  Format.pp_print_flush out_fmt ();
  Format.pp_print_flush err_fmt ();
  if Buffer.length out_buffer > 0 then stdout (Buffer.contents out_buffer);
  if Buffer.length err_buffer > 0 then stderr (Buffer.contents err_buffer);
  match parsed with Ok `Help | Ok `Version -> 0 | Error _ -> 2 | Ok (`Ok f) -> f ()

let run ?commands ?config_commands ?service_command ?validate ?telemetry ~name ~config
    ~pp_err program =
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
            try Ok (Eio.Path.load Eio.Path.(env#fs / path)) with
            | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) -> Error `Missing
            | Eio.Io _ as exn -> Error (`Unreadable (Printexc.to_string exn))
          in
          run_for_test ?commands ?config_commands ?service_command ?validate ?telemetry
            ~on_switch ~env
            ~journal:(Eta_observability.Logger.Reporter.journal env#stderr)
            ~name ~config ~pp_err ~getenv:Sys.getenv_opt ~read
            ~stderr:(fun text -> Eio.Flow.copy_string text env#stderr)
            ~stdout:(fun text -> Eio.Flow.copy_string text env#stdout)
            ~argv:Sys.argv program))
