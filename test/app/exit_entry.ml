(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
(* ^ncaps-0mvw ^nfloor-6n2e: returning and exiting Doors agree. *)
type outcome = { code : int; stdout : string; stderr : string }

let spawn ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >)
    mode =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let fixture =
            Filename.concat (Filename.dirname Sys.executable_name) "exit_fixture.exe"
          in
          let child =
            match
              Ox_process.Child.spawn ~caps ~sw ~clock:env#clock ~mgr:env#process_mgr
                ~argv:[ fixture; mode ] ~grace:(Ox.Duration.ms 50)
                ~stdout:Ox_process.Child.Pipe ~stderr:Ox_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid exit fixture spawn"
          in
          let stdout =
            match Ox_process.Child.stdout child with
            | Some value -> value
            | None ->
                Alcotest.fail
                  "missing app/exit_entry fixture: (Ox_process.Child.stdout child)"
          in
          let stderr =
            match Ox_process.Child.stderr child with
            | Some value -> value
            | None ->
                Alcotest.fail
                  "missing app/exit_entry fixture: (Ox_process.Child.stderr child)"
          in
          let reader = Eio.Buf_read.of_flow ~max_size:4096 stdout in
          let status =
            Eio.Time.with_timeout_exn env#clock 10. (fun () ->
                Ox_process.Child.await child)
          in
          let code =
            match status with
            | Ox_process.Child.Exited code -> code
            | _ -> Alcotest.fail "exit fixture did not exit"
          in
          let stdout = Eio.Buf_read.take_all reader in
          let stderr = Eio.Flow.read_all stderr in
          { code; stdout; stderr }))

let parity ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. >)
    () =
  List.iter
    (fun (mode, expected) ->
      let returned = spawn ~caps ("return-" ^ mode) in
      Alcotest.(check int) "returning fixture returns normally" 0 returned.code;
      Alcotest.(check string)
        "returning status after cleanup"
        (Printf.sprintf "released\nstatus=%d\n" expected)
        returned.stdout;
      List.iter
        (fun entry ->
          let exited = spawn ~caps (entry ^ "-" ^ mode) in
          Alcotest.(check int) "same exit status" expected exited.code;
          Alcotest.(check string) "cleanup before exit" "released\n" exited.stdout;
          Alcotest.(check string)
            "identical Cause rendering" returned.stderr exited.stderr)
        [ "exit"; "args" ])
    [ ("success", 0); ("fail", 23); ("defect", 2); ("stop", 0) ]

let () =
  Alcotest.run "Door exit"
    [
      ( "^ncaps-0mvw",
        [
          Alcotest.test_case "return and exit parity" `Quick (fun () ->
              parity ~caps:(Ox_test.powerbox ()) ());
        ] );
    ]
