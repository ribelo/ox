(* ^nwake-27rc ^nwake-y4cx: ticker gating/cadence/cleanup and a real Door stop. *)
module Logger = Ox_observability.Logger

let check_int = Alcotest.(check int)
let check_bool = Alcotest.(check bool)

let contains text part =
  let rec loop i =
    i + String.length part <= String.length text
    && (String.sub text i (String.length part) = part || loop (i + 1))
  in
  loop 0

let ticker backend interval_ms () =
  Eio_main.run (fun real ->
      let clock = Eio_mock.Clock.make () in
      let env =
        object
          method backend_id = backend
          method clock = clock
          method mono_clock = real#mono_clock
          method stderr = real#stderr
        end
      in
      let memory = Logger.Memory.create () in
      let logger =
        Logger.create ~service:"test" ~clock ~mono_clock:real#mono_clock
          ~reporter:(Logger.Memory.reporter memory)
          ()
      in
      Eio.Switch.run (fun sw ->
          Ox_app.posix_wakeup ~sw ~interval_ms ~logger env;
          let enabled = backend = "posix" && interval_ms > 0 in
          check_bool "only posix with nonzero interval arms a timer" enabled
            (Eio_mock.Clock.try_advance clock);
          if enabled then begin
            Alcotest.(check (float 0.000001))
              "first wake at the selected interval"
              (float_of_int interval_ms /. 1000.)
              (Eio.Time.now clock);
            Eio.Fiber.yield ();
            check_bool "daemon rearms" true (Eio_mock.Clock.try_advance clock);
            Alcotest.(check (float 0.000001))
              "second wake"
              (2. *. float_of_int interval_ms /. 1000.)
              (Eio.Time.now clock);
            Eio.Fiber.yield ()
          end);
      check_bool "no timer remains when its outer switch ends" false
        (Eio_mock.Clock.try_advance clock);
      match Logger.Memory.records memory with
      | [ record ] ->
          Alcotest.(check string) "startup choice" "posix wakeup" record.Logger.msg;
          let effective = if backend = "posix" then interval_ms else 0 in
          check_int "effective interval logged once" 1
            (List.length
               (Logger.Memory.find ~field:("wakeup_ms", string_of_int effective) memory));
          check_int "actual backend logged, not EIO_BACKEND" 1
            (List.length (Logger.Memory.find ~field:("backend", backend) memory))
      | records -> check_int "one startup record" 1 (List.length records))

type outcome = { code : int; stdout : string; stderr : string }

(* An OS timeout still fires if ppoll stops the child runtime. The parent's Eio
   deadline bounds its own wait; it does not mask the fixture's cleanup race. *)
let fixture ?option_ms ?env_ms ?(cleanup = false) ?(owned = false)
    ?(quiet_journal = false) () =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let path =
            Filename.concat (Filename.dirname Sys.executable_name) "wakeup_fixture.exe"
          in
          let variables =
            Unix.environment () |> Array.to_list
            |> List.filter (fun entry ->
                not
                  (List.exists
                     (fun prefix -> String.starts_with ~prefix entry)
                     [ "EIO_BACKEND="; "OX_POSIX_WAKEUP_MS="; "WAKEUP_FIXTURE_" ]))
          in
          let variables =
            variables @ [ "EIO_BACKEND=posix" ]
            @ (match env_ms with None -> [] | Some n -> [ "OX_POSIX_WAKEUP_MS=" ^ n ])
            @ (match option_ms with
              | None -> []
              | Some n -> [ "WAKEUP_FIXTURE_OPTION_MS=" ^ string_of_int n ])
            @ (if cleanup then [ "WAKEUP_FIXTURE_CLEANUP=1" ] else [])
            @ if quiet_journal then [ "WAKEUP_FIXTURE_QUIET_JOURNAL=1" ] else []
          in
          let child =
            match
              Ox_process.Child.spawn ~caps:(Ox_test.powerbox ()) ~sw ~clock:env#clock
                ~mgr:env#process_mgr
                ~argv:
                  ([ "timeout"; "--kill-after=1"; "5"; path ]
                  @ if owned then [ "owned" ] else [])
                ~env:(Array.of_list variables) ~grace:(Ox.Duration.ms 50)
                ~stdout:Ox_process.Child.Pipe ~stderr:Ox_process.Child.Pipe ~fds:[] ()
            with
            | Ok child -> child
            | Error _ -> Alcotest.fail "invalid wakeup fixture spawn"
          in
          let status =
            Eio.Time.with_timeout_exn env#clock 10. (fun () ->
                Ox_process.Child.await child)
          in
          let code =
            match status with
            | Ox_process.Child.Exited code -> code
            | _ -> Alcotest.fail "fixture killed"
          in
          let stdout = Eio.Flow.read_all (Option.get (Ox_process.Child.stdout child)) in
          let stderr = Eio.Flow.read_all (Option.get (Ox_process.Child.stderr child)) in
          { code; stdout; stderr }))

let check_choice expected outcome =
  check_int "Door returns success" 0 outcome.code;
  check_bool "actual posix backend logged" true
    (contains outcome.stderr "\"backend\":\"posix\"");
  check_bool "selected interval logged" true
    (contains outcome.stderr ("\"wakeup_ms\":" ^ string_of_int expected));
  check_int "only one startup line" 1
    (List.length
       (String.split_on_char '\n' outcome.stderr
       |> List.filter (fun line -> contains line "posix wakeup")))

let default () = check_choice 50 (fixture ())
let disabled () = check_choice 0 (fixture ~env_ms:"0" ())
let overridden () = check_choice 7 (fixture ~env_ms:"0" ~option_ms:7 ())
let environment () = check_choice 9 (fixture ~env_ms:"9" ())

let owned_stderr () =
  let outcome = fixture ~owned:true ~option_ms:50 () in
  check_int "owned command completes with ticker enabled" 0 outcome.code;
  Alcotest.(check string) "owned command keeps stderr empty" "" outcome.stderr

let journal_filter () =
  let outcome = fixture ~quiet_journal:true () in
  check_int "service succeeds with quiet journal" 0 outcome.code;
  Alcotest.(check string) "journal_level filters startup log" "" outcome.stderr

let invalid () =
  List.iter
    (fun value ->
      check_bool "invalid interval rejected" true ((fixture ~env_ms:value ()).code <> 0))
    [ "-1"; "invalid" ]

let protected_sigterm () =
  let outcome = fixture ~cleanup:true () in
  check_choice 50 outcome;
  Alcotest.(check string)
    "protected cleanup completed before clean SIGTERM exit"
    "cleanup start\ncleanup complete\n" outcome.stdout

let () =
  Alcotest.run "posix wakeup"
    [
      ( "^nwake-y4cx",
        [
          Alcotest.test_case "posix 50 ms daemon" `Quick (ticker "posix" 50);
          Alcotest.test_case "custom 7 ms cadence" `Quick (ticker "posix" 7);
          Alcotest.test_case "zero creates no daemon" `Quick (ticker "posix" 0);
          Alcotest.test_case "linux creates no daemon despite EIO_BACKEND=posix" `Quick
            (ticker "linux" 50);
          Alcotest.test_case "default and one startup log" `Quick default;
          Alcotest.test_case "owned command stderr stays empty with ticker on" `Quick
            owned_stderr;
          Alcotest.test_case "journal threshold filters startup log" `Quick journal_filter;
          Alcotest.test_case "env disables" `Quick disabled;
          Alcotest.test_case "env configures" `Quick environment;
          Alcotest.test_case "Door option wins over env" `Quick overridden;
          Alcotest.test_case "malformed and negative intervals rejected" `Quick invalid;
        ] );
      ( "^nwake-27rc",
        [ Alcotest.test_case "SIGTERM protected child cleanup" `Quick protected_sigterm ]
      );
    ]
