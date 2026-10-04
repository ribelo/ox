(* ^nwake-27rc: SIGTERM stops the program, not the outer wake-up daemon.
   This finally block exercises Eio's release-hook reaping and raw Eio.Process children
   with cancellation protected; an inner-scope ticker would already be cancelled. *)
let pp_err _ (_ : [ `Never ]) = ()

let main ~(caps : < Ox_caps.Cap.env ; Ox_caps.Cap.exit ; Ox_caps.Cap.signal ; .. >) () =
  let wakeup_ms =
    Option.map int_of_string (Ox_caps.Cap_sys.getenv_opt ~caps "WAKEUP_FIXTURE_OPTION_MS")
  in
  let cleanup = Ox_caps.Cap_sys.getenv_opt ~caps "WAKEUP_FIXTURE_CLEANUP" = Some "1" in
  let journal_level =
    if Ox_caps.Cap_sys.getenv_opt ~caps "WAKEUP_FIXTURE_QUIET_JOURNAL" = Some "1" then
      Some Ox_observability.Logger.Error
    else None
  in
  let commands_with_env env run_owned =
    let owned () =
      run_owned (fun _sw ->
          for _ = 1 to 100 do
            Eio.Process.run env.Ox_app.Env.base#process_mgr [ "/bin/sh"; "-c"; "exit 0" ]
          done;
          Ok ())
    in
    [ Cmdliner.Cmd.v (Cmdliner.Cmd.info "owned") (Cmdliner.Term.const owned) ]
  in
  Ox_caps.Cap_stdlib.exit ~caps
    (Ox_app.run_with_args ?wakeup_ms ?journal_level ~commands_with_env
       ~service_args:(Cmdliner.Term.const ()) ~config:Ox_app.Config.none
       ~name:"wakeup-fixture" ~pp_err (fun env _source () () sw ->
         if not cleanup then Ok ()
         else
           let base = env.Ox_app.Env.base in
           Fun.protect
             ~finally:(fun () ->
               Eio.Cancel.protect (fun () ->
                   Eio.Flow.copy_string "cleanup start\n" base#stdout;
                   (* Its switch closes without awaiting the child. Eio's protected
                      release hook kills and reaps it after cancelling its daemon. *)
                   let child =
                     Eio.Switch.run (fun cleanup_sw ->
                         Eio.Process.spawn ~sw:cleanup_sw base#process_mgr
                           [ "/bin/sh"; "-c"; "exec sleep 10" ])
                   in
                   (match Eio.Process.await child with
                   | `Signaled _ -> ()
                   | _ -> failwith "cleanup child was not stopped and reaped");
                   (* Amplify the signal timing race after cancellation without
                      an Eio deadline that could substitute for the ticker. *)
                   for _ = 1 to 1000 do
                     Eio.Process.run base#process_mgr [ "/bin/sh"; "-c"; "exit 0" ]
                   done;
                   Eio.Flow.copy_string "cleanup complete\n" base#stdout))
             (fun () ->
               Ox_caps.Cap_unix.kill ~caps (Unix.getpid ()) Sys.sigterm;
               Ox_app.serve ~sw ())))

let () = main ~caps:(Ox_test.powerbox ()) ()
