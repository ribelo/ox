(* nlimit-s3f4: independently spawned Door for real OS signals. *)
type config = { port : int }

let config =
  Eta_schema.(
    record1 ~name:"signal-fixture"
      (fun port -> { port })
      (required "port" int (fun c -> c.port))
      ~equal:( = ) ())

let pp_err _fmt (_ : [ `Never ]) = ()

let () =
  let code =
    Eta_app.run ~name:"signal-fixture" ~config ~pp_err (fun env _ sw ->
        Eio.Switch.on_release sw (fun () ->
            Eta_observability.Logger.info env.Eta_app.Env.logger "signal stopped");
        Eio.Flow.copy_string "ready\n" env.Eta_app.Env.base#stdout;
        Eta_app.serve ~sw ())
  in
  exit code
