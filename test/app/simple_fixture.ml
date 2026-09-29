(* ^nfloor-6n2e: the OxApp.Simple counterpart, run for real: no config type, no file. The
   mode comes from the environment because the Door owns argv. *)
let pp_err fmt = function `Usage -> Format.pp_print_string fmt "usage error"
let say env text = Eio.Flow.copy_string (text ^ "\n") env.Ox_app.Env.base#stdout

let () =
  let mode = Option.value (Sys.getenv_opt "SIMPLE_MODE") ~default:"serve" in
  let code =
    Ox_app.run_simple ~name:"simple-fixture" ~pp_err
      ~exit_code:(function `Usage -> 64)
      (fun env sw ->
        let clock = env.Ox_app.Env.base#clock in
        match mode with
        | "fail" -> Error `Usage
        | "defect" -> failwith "simple defect"
        | "background" ->
            (* OxApp's forkUser: the body returns, the fork still finishes. *)
            Eio.Fiber.fork ~sw (fun () ->
                Eio.Time.sleep clock 0.2;
                say env "fork finished");
            say env "body done";
            Ok ()
        | _ ->
            Eio.Switch.on_release sw (fun () -> say env "released");
            Eio.Fiber.fork_daemon ~sw (fun () -> Eio.Fiber.await_cancel ());
            say env "ready";
            Ox_app.serve ~sw ())
  in
  exit code
