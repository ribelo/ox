(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
(* Row 46, story ^nfloor-6n2e: every item of Ox's OxApp has a Door counterpart or a
   recorded reason not to. One case per item; the table of items is docs/design/ox-floor.md
   (section OxApp). Cases that need the real Door (Eio_main, argv, signals) spawn
   simple_fixture.exe; the rest run the Door in process. *)
open Ox_app

let check_int = Alcotest.(check int)
let check_string = Alcotest.(check string)

let contains hay needle =
  let rec go i =
    i + String.length needle <= String.length hay
    && (String.sub hay i (String.length needle) = needle || go (i + 1))
  in
  go 0

type outcome = { code : int; stdout : string; stderr : string }

(* Spawn the Simple fixture in [mode]; [after_ready] runs once its first line was read. *)
let spawn_simple
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; .. >) ?(after_ready = fun _ -> ()) mode =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let fixture =
            Filename.concat (Filename.dirname Sys.executable_name) "simple_fixture.exe"
          in
          let child =
            match
              Ox_process.Child.spawn ~caps ~sw ~clock:env#mono_clock ~mgr:env#process_mgr
                ~argv:[ fixture ]
                ~env:
                  (Array.append
                     (Ox_caps.Cap_unix.environment ~caps ())
                     [| "SIMPLE_MODE=" ^ mode |])
                ~grace:(Ox.Duration.ms 50) ~stdout:Ox_process.Child.Pipe
                ~stderr:Ox_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid simple fixture spawn"
          in
          let stdout =
            match Ox_process.Child.stdout child with
            | Some value -> value
            | None ->
                Alcotest.fail "missing app/oxapp fixture: (Ox_process.Child.stdout child)"
          in
          let stderr =
            match Ox_process.Child.stderr child with
            | Some value -> value
            | None ->
                Alcotest.fail "missing app/oxapp fixture: (Ox_process.Child.stderr child)"
          in
          let reader = Eio.Buf_read.of_flow ~max_size:4096 stdout in
          after_ready (child, reader, env#clock);
          let status =
            Eio.Time.with_timeout_exn env#clock 10. (fun () ->
                Ox_process.Child.await child)
          in
          let code =
            match status with
            | Ox_process.Child.Exited code -> code
            | _ -> Alcotest.fail "simple fixture did not exit"
          in
          let stdout = Eio.Buf_read.take_all reader in
          let stderr = Eio.Flow.read_all stderr in
          { code; stdout; stderr }))

(* OxApp.Simple: run(using Ox): Unit — no config, no arguments, the root scope in hand. *)
let simple_variant
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; .. >) () =
  let outcome =
    spawn_simple ~caps "serve" ~after_ready:(fun (child, reader, clock) ->
        check_string "Door ready without any config file" "ready"
          (Eio.Time.with_timeout_exn clock 5. (fun () -> Eio.Buf_read.line reader));
        Ox_process.Child.signal child Sys.sigterm)
  in
  (* SIGINT/SIGTERM: the root scope is interrupted, releases run, the exit is Ox's
     default interruptedExitCode, 0 *)
  check_int "SIGTERM is a clean stop, exit 0" 0 outcome.code;
  check_string "the scope's release ran before the process exited" "released\n"
    outcome.stdout

(* forkUser: a background fork of the app's own scope is waited for; the exit is 0. *)
let background_forks
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; .. >) () =
  let outcome = spawn_simple ~caps "background" in
  check_int "exit 0" 0 outcome.code;
  check_string "the fork finished before the Door returned" "body done\nfork finished\n"
    outcome.stdout

(* OxApp.WithEitherErrors.handleError: a typed error becomes the exit code. *)
let typed_error_exit_code
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; .. >) () =
  let outcome = spawn_simple ~caps "fail" in
  check_int "typed error through exit_code" 64 outcome.code;
  Alcotest.(check bool) "rendered on stderr" true (contains outcome.stderr "usage error")

(* handleException: a defect is rendered in full and exits 2 (Ox's Simple: stack trace,
   exit 1); a typed failure keeps its own code, so the two can be told apart. *)
let defect_rendering
    ~(caps :
       < Ox_caps.Cap.env
       ; Ox_caps.Cap.fork
       ; Ox_caps.Cap.exec
       ; Ox_caps.Cap.fs_write
       ; .. >) () =
  let outcome = spawn_simple ~caps "defect" in
  check_int "defect exits 2" 2 outcome.code;
  Alcotest.(check bool) "cause on stderr" true (contains outcome.stderr "simple defect")

(* run(args: Vector[String]): ExitCode — arguments, an exit code, through the Door in
   process: typed service args reach the program and typed failures pick the code. *)
let args_and_exit_code () =
  let open Cmdliner in
  Ox_test.run (fun env _ ->
      let seen = ref [] in
      let invoke argv =
        run_for_test_with_args
          ~service_args:Arg.(value & pos_all string [] & info [])
          ~env ~name:"demo" ~config:Config.none
          ~pp_err:(fun fmt (`Failed n) -> Format.fprintf fmt "failed %d" n)
          ~getenv:(fun _ -> None)
          ~read:(fun _ -> Error `Missing)
          ~exit_code:(function `Failed n -> n)
          ~journal:
            (Ox_observability.Logger.Memory.reporter
               (Ox_observability.Logger.Memory.create ()))
          ~stdout:ignore ~stderr:ignore ~argv
          (fun _ _ () args _ ->
            seen := args;
            match args with
            | [ "boom"; code ] -> Error (`Failed (int_of_string code))
            | _ -> Ok ())
      in
      check_int "success" 0 (invoke [| "demo"; "run"; "a"; "b" |]);
      Alcotest.(check (list string)) "args reached the program" [ "a"; "b" ] !seen;
      check_int "typed failure exit code" 23 (invoke [| "demo"; "run"; "boom"; "23" |]))

(* Config.none: the empty config any document decodes to. *)
let no_config () =
  Alcotest.(check bool)
    "decodes any document" true
    (Config.none.of_yojson (Yojson.Safe.from_string {|{"anything": [1, 2]}|}) = Ok ());
  check_string "encodes empty" "{}" (Yojson.Safe.to_string (Config.none.yojson_of_t ()));
  Alcotest.(check bool)
    "overrides nothing" true
    (Config.none.env ~getenv:(fun _ -> Some "x") () = ())

let () =
  Alcotest.run "ox_app oxapp"
    [
      ( "OxApp parity ^nfloor-6n2e",
        [
          Alcotest.test_case "^nfloor-6n2e run args: exit code and typed error handler"
            `Quick args_and_exit_code;
          Alcotest.test_case "^nfloor-6n2e OxApp.Simple and SIGTERM stop" `Quick
            (fun () -> simple_variant ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "^nfloor-6n2e forkUser: background forks in the app scope"
            `Quick (fun () -> background_forks ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "^nfloor-6n2e handleError" `Quick (fun () ->
              typed_error_exit_code ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "^nfloor-6n2e handleException" `Quick (fun () ->
              defect_rendering ~caps:(Ox_test.powerbox ()) ());
          Alcotest.test_case "^nfloor-6n2e no config" `Quick no_config;
        ] );
    ]
