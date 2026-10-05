(* nlimit-s3f4: independently spawned Door for real OS signals.
   ^napp-57qi: it is also the only executable that proves Ox_app.run, not only
   run_for_test, runs ?validate before the program.
   ^nnoschema-5mdj: the config type is a plain record with a derived codec — the
   shape a consumer writes — so this fixture exercises the Door's real config path.
   ^napp-idii: with `telemetry = true` it is also the only executable that proves the
   Door's telemetry hook on the real SIGTERM path: the reporter the config switches on
   sees the record the program logs when the signal stops it, and the hook's root-switch
   resource flushes before the process exits.
   ^notel-1stb: with `otlp_endpoint` it is also the only executable that proves a real
   ox_otel exporter on that path: the exporter's own release hook exports the record
   logged while the signal stops it, and `otlp_shutdown` adds the pre-fix consumer
   pattern — an explicit shutdown registered with the same switch's release — beside it.
   ^napp-9x0s: the port carries a default too, so the same executable proves the real Door
   starts with no config file at the default path; the tests that write a port still
   override it.
   ^napp-d5e4: the Door's start command is called `serve` here, so a test that asks for it
   by name proves Ox_app.run forwards ?service_command; the bare spawns prove the group's
   default term starts the program whatever that command is called. *)
type config = {
  port : int; [@json.default 4242]
  telemetry : bool; [@json.default false]
  otlp_endpoint : string option;
  (* ^notel-1stb: the pre-fix consumer pattern — the exporter's shutdown registered with
     the root switch's release — which used to wait for the daemon the switch had
     already cancelled and deadlock the stop. *)
  otlp_shutdown : bool; [@json.default false]
}
[@@deriving yojson]

let config : config Ox_app.Config.t =
  {
    of_yojson = config_of_yojson;
    yojson_of_t = yojson_of_config;
    env = (fun ~getenv:_ settings -> settings);
  }

(* Port 7 is this fixture's rejectable value: the test that writes it expects the
   validator to stop the Door before the program prints anything. *)
let validate _ (cfg : config) =
  if cfg.port = 7 then
    Error [ { Ox_app.Config.pointer = "/port"; message = "port rejected by validator" } ]
  else Ok ()

let pp_err _fmt (_ : [ `Never ]) = ()

(* ^napp-idii: export switched by the program's own config, the shape a service writes.
   The reporter writes to stdout so the test sees the record the program logs when the
   signal stops it; the flush line is a root-switch release registered before the
   program's own, so it runs after it (releases are LIFO) and before the Door returns. *)
let telemetry ~sw (env : Eio_unix.Stdenv.base Ox_app.Env.t) (cfg : config) =
  if not cfg.telemetry then { Ox_app.reporters = []; span_ids = None }
  else begin
    let reporter =
      Ox_observability.Logger.Reporter.writer (fun line ->
          Eio.Flow.copy_string ("telemetry " ^ line) env.Ox_app.Env.base#stdout)
    in
    Eio.Switch.on_release sw (fun () ->
        Eio.Flow.copy_string "telemetry flushed\n" env.Ox_app.Env.base#stdout);
    match cfg.otlp_endpoint with
    | None -> { Ox_app.reporters = [ reporter ]; span_ids = None }
    | Some endpoint ->
        (* ^notel-1stb: a real exporter. Unless [otlp_shutdown] asks for the pre-fix
           consumer pattern, nothing calls [Ox_otel.shutdown]: the exporter's own
           release hook on the root switch exports whatever the queue still holds when
           the signal stops the Door. *)
        let base = env.Ox_app.Env.base in
        let client = Ox_http.Client.create ~sw ~net:base#net ~clock:base#clock () in
        let exporter =
          match
            Ox_otel.create ~ending_budget:(Ox.Duration.ms 100) ~caps:env.Ox_app.Env.caps
              ~sw ~clock:base#clock ~http_client:client ~endpoint
              ~service_name:"signal-fixture" ()
          with
          | Ok exporter -> exporter
          | Error error ->
              failwith (Format.asprintf "otlp exporter: %a" Ox_otel.pp_error error)
        in
        if cfg.otlp_shutdown then
          Eio.Switch.on_release sw (fun () ->
              match Ox_otel.shutdown exporter with
              | Ok () -> ()
              | Error error ->
                  Eio.Flow.copy_string
                    (Format.asprintf "otlp shutdown: %a\n" Ox_otel.pp_error error)
                    base#stdout);
        {
          Ox_app.reporters = [ reporter; Ox_otel.reporter exporter ];
          span_ids = Some (Ox_otel.span_ids exporter);
        }
  end

let main ~(caps : < Ox_caps.Cap.exit ; .. >) () =
  let code =
    Ox_app.run_with_args ~name:"signal-fixture" ~config ~validate ~pp_err ~telemetry
      ~service_args:(Cmdliner.Term.const ())
      ~read_file:(fun env path ->
        Ox_app.Config.read_regular ~max_bytes:1024 Eio.Path.(env#fs / path))
      ~commands_with_env:(fun env run_owned ->
        let long =
          Cmdliner.Term.const (fun () ->
              run_owned (fun sw ->
                  Eio.Switch.on_release sw (fun () ->
                      Eio.Flow.copy_string "command released\n" env.Ox_app.Env.base#stdout);
                  Eio.Flow.copy_string "ready\n" env.Ox_app.Env.base#stdout;
                  Ox_app.serve ~sw ()))
        in
        [ Cmdliner.Cmd.v (Cmdliner.Cmd.info "long") long ])
      ~commands_with_env_code:(fun env _run_owned run_owned_code ->
        let long =
          Cmdliner.Term.const (fun () ->
              run_owned_code (fun sw ->
                  Eio.Switch.on_release sw (fun () ->
                      Eio.Flow.copy_string "code command released\n"
                        env.Ox_app.Env.base#stdout);
                  Eio.Flow.copy_string "ready\n" env.Ox_app.Env.base#stdout;
                  (* ^safe-xls8 ^safe-pufa ^nlint-hxar: The signal fixture tests owned interruption and the command exit code; a normal serve reply is incidental. *)
                  (let _serve_result =
                     Ox_app.serve ~sw ()
                       [@@ox.allow
                         "ox-discarded-result: signal fixture observes owned \
                          interruption and exit code 19 rather than a normal serve reply"]
                   in
                   ());
                  19))
        in
        [ Cmdliner.Cmd.v (Cmdliner.Cmd.info "long-code") long ])
      ~service_command:"serve"
      (fun env _source _cfg () sw ->
        Eio.Switch.on_release sw (fun () ->
            Ox_observability.Logger.info env.Ox_app.Env.logger "signal stopped");
        (* ^napp-78pf: a live service fiber must propagate cancellation, not only
           the Door main fiber. Eio wraps the switch failure in [Cancelled]. *)
        Eio.Fiber.fork_daemon ~sw (fun () -> Eio.Fiber.await_cancel ());
        Eio.Flow.copy_string "ready\n" env.Ox_app.Env.base#stdout;
        Ox_app.serve ~sw ())
  in
  Ox_caps.Cap_stdlib.exit ~caps code

let () = main ~caps:(Ox_test.powerbox ()) ()
