(* nlimit-s3f4: independently spawned Door for real OS signals.
   ^napp-57qi: it is also the only executable that proves Eta_app.run, not only
   run_for_test, runs ?validate before the program.
   ^nnoschema-5mdj: the config type is a plain record with a derived codec — the
   shape a consumer writes — so this fixture exercises the Door's real config path.
   ^napp-idii: with `telemetry = true` it is also the only executable that proves the
   Door's telemetry hook on the real SIGTERM path: the reporter the config switches on
   sees the record the program logs when the signal stops it, and the hook's root-switch
   resource flushes before the process exits. *)
type config = { port : int; telemetry : bool [@json.default false] } [@@deriving yojson]

let config : config Eta_app.Config.t =
  {
    of_yojson = config_of_yojson;
    yojson_of_t = yojson_of_config;
    env = (fun ~getenv:_ settings -> settings);
  }

(* Port 7 is this fixture's rejectable value: the test that writes it expects the
   validator to stop the Door before the program prints anything. *)
let validate _ (cfg : config) =
  if cfg.port = 7 then
    Error [ { Eta_app.Config.pointer = "/port"; message = "port rejected by validator" } ]
  else Ok ()

let pp_err _fmt (_ : [ `Never ]) = ()

(* ^napp-idii: export switched by the program's own config, the shape a service writes.
   The reporter writes to stdout so the test sees the record the program logs when the
   signal stops it; the flush line is a root-switch release registered before the
   program's own, so it runs after it (releases are LIFO) and before the Door returns. *)
let telemetry ~sw (env : Eio_unix.Stdenv.base Eta_app.Env.t) (cfg : config) =
  if not cfg.telemetry then { Eta_app.reporters = []; span_ids = None }
  else begin
    let reporter =
      Eta_observability.Logger.Reporter.writer (fun line ->
          Eio.Flow.copy_string ("telemetry " ^ line) env.Eta_app.Env.base#stdout)
    in
    Eio.Switch.on_release sw (fun () ->
        Eio.Flow.copy_string "telemetry flushed\n" env.Eta_app.Env.base#stdout);
    { Eta_app.reporters = [ reporter ]; span_ids = None }
  end

let () =
  let code =
    Eta_app.run ~name:"signal-fixture" ~config ~validate ~pp_err ~telemetry
      (fun env _ sw ->
        Eio.Switch.on_release sw (fun () ->
            Eta_observability.Logger.info env.Eta_app.Env.logger "signal stopped");
        (* ^napp-78pf: a live service fiber must propagate cancellation, not only
           the Door main fiber. Eio wraps the switch failure in [Cancelled]. *)
        Eio.Fiber.fork_daemon ~sw (fun () -> Eio.Fiber.await_cancel ());
        Eio.Flow.copy_string "ready\n" env.Eta_app.Env.base#stdout;
        Eta_app.serve ~sw ())
  in
  exit code
