(* nlimit-s3f4: independently spawned Door for real OS signals.
   ^napp-57qi: it is also the only executable that proves Eta_app.run, not only
   run_for_test, runs ?validate before the program. *)
type config = { port : int }

let config =
  Eta_schema.(
    record1 ~name:"signal-fixture"
      (fun port -> { port })
      (required "port" int (fun c -> c.port))
      ~equal:( = ) ())

(* Port 7 is this fixture's rejectable value: the test that writes it expects the
   validator to stop the Door before the program prints anything. *)
let validate _ (cfg : config) =
  if cfg.port = 7 then
    Error [ { Eta_app.Config.pointer = "/port"; message = "port rejected by validator" } ]
  else Ok ()

let pp_err _fmt (_ : [ `Never ]) = ()

let () =
  let code =
    Eta_app.run ~name:"signal-fixture" ~config ~validate ~pp_err (fun env _ sw ->
        Eio.Switch.on_release sw (fun () ->
            Eta_observability.Logger.info env.Eta_app.Env.logger "signal stopped");
        Eio.Flow.copy_string "ready\n" env.Eta_app.Env.base#stdout;
        Eta_app.serve ~sw ())
  in
  exit code
