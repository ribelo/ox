open Ox

(* ^nmono-8jcy ^nmono-r2pk: exercise the upstream monotonic boundary, not a
   second race implementation. All clock movement is backend-owned virtual time. *)
type error = [ `Timeout | `Body ]

let error =
  Alcotest.testable
    (fun fmt -> function
      | `Timeout -> Format.pp_print_string fmt "Timeout"
      | `Body -> Format.pp_print_string fmt "Body")
    ( = )

let check_result label expected actual =
  Alcotest.(check (result int error)) label expected actual

let elapsed_ns clock start =
  Mtime.Span.to_uint64_ns (Mtime.span start (Eio.Time.Mono.now clock))

let outcomes () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      List.iter
        (fun expected ->
          let actual =
            Timeout.timeout_mono ~clock (Duration.ms 50) (fun () -> expected)
          in
          check_result "callback settlement is returned unchanged" expected actual;
          Alcotest.(check bool) "same result value" true (expected == actual);
          Alcotest.(check bool)
            "losing timer removed" false
            (Eio_mock.Clock.Mono.try_advance clock))
        [ Ok 42; Error `Body; Error `Timeout ];
      let start = Eio.Time.Mono.now clock in
      let actual =
        Timeout.timeout_mono ~clock (Duration.ms 50) (fun () ->
            Eio.Time.Mono.sleep clock 0.01;
            Ok 7)
      in
      check_result "success after suspension" (Ok 7) actual;
      Alcotest.(check int64)
        "body finished before deadline" 10_000_000L (elapsed_ns clock start);
      Alcotest.(check bool)
        "suspended success cancels timer" false
        (Eio_mock.Clock.Mono.try_advance clock))

let expiry_cleanup () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      let start = Eio.Time.Mono.now clock in
      let body_cleaned = ref false and child_cleaned = ref false in
      let effects = ref 0 in
      let actual =
        Timeout.timeout_mono ~clock (Duration.ms 250) (fun () ->
            Eio.Switch.run (fun sw ->
                Eio.Switch.on_release sw (fun () ->
                    Eio.Time.Mono.sleep clock 0.025;
                    body_cleaned := true);
                let started, ready = Eio.Promise.create () in
                Eio.Fiber.fork ~sw (fun () ->
                    Fun.protect
                      (fun () ->
                        Eio.Promise.resolve ready ();
                        Eio.Fiber.await_cancel ())
                      ~finally:(fun () -> child_cleaned := true));
                Eio.Promise.await started;
                incr effects;
                Eio.Time.Mono.sleep clock 1.;
                Ok 9))
      in
      check_result "deadline result" (Error `Timeout) actual;
      Alcotest.(check bool) "callback switch cleanup awaited" true !body_cleaned;
      Alcotest.(check bool) "callback child cancellation awaited" true !child_cleaned;
      Alcotest.(check int64)
        "deadline plus protected cleanup" 275_000_000L (elapsed_ns clock start);
      Alcotest.(check int) "effects are not rolled back" 1 !effects;
      Alcotest.(check bool)
        "no remaining sleeper" false
        (Eio_mock.Clock.Mono.try_advance clock))

exception Defect of string

let defects () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      let check_defect label boom callback =
        match Timeout.timeout_mono ~clock (Duration.ms 10) callback with
        | exception ex -> Alcotest.(check bool) label true (ex == boom)
        | _ -> Alcotest.fail "defect was returned as a typed timeout"
      in
      let boom = Defect "callback" in
      check_defect "callback exception preserved" boom (fun () -> raise boom);
      let boom = Defect "cleanup" in
      check_defect "cleanup defect is not swallowed by deadline" boom (fun () ->
          Eio.Switch.run (fun sw ->
              Eio.Switch.on_release sw (fun () -> raise boom);
              Eio.Fiber.await_cancel ()));
      Alcotest.(check bool)
        "defects cancel the timer" false
        (Eio_mock.Clock.Mono.try_advance clock))

let caller_switch () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      let released = ref false in
      Eio.Switch.run (fun sw ->
          let actual =
            Timeout.timeout_mono ~clock (Duration.ms 10) (fun () ->
                Eio.Switch.on_release sw (fun () -> released := true);
                Eio.Fiber.await_cancel ())
          in
          check_result "deadline inside caller switch" (Error `Timeout) actual;
          Eio.Switch.check sw;
          Alcotest.(check bool) "caller resources not released by timeout" false !released;
          let next = Eio.Fiber.fork_promise ~sw (fun () -> 42) in
          Alcotest.(check int)
            "caller switch still accepts work" 42 (Eio.Promise.await_exn next));
      Alcotest.(check bool) "caller owns eventual release" true !released)

let external_cancel () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      let cleaned = ref false in
      let start = Eio.Time.Mono.now clock in
      let actual =
        Eio.Cancel.sub (fun context ->
            Eio.Switch.run (fun outer ->
                Eio.Fiber.fork ~sw:outer (fun () ->
                    Eio.Time.Mono.sleep clock 0.05;
                    Eio.Cancel.cancel context (Defect "external interruption"));
                Scope.run (fun _ ->
                    Timeout.timeout_mono ~clock (Duration.seconds 1) (fun () ->
                        Eio.Switch.run (fun sw ->
                            Eio.Switch.on_release sw (fun () -> cleaned := true);
                            Eio.Fiber.await_cancel ())))))
      in
      (match actual with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "external cancellation became a deadline result");
      Alcotest.(check bool) "externally cancelled callback released" true !cleaned;
      Alcotest.(check int64)
        "external interrupt precedes deadline" 50_000_000L (elapsed_ns clock start);
      Alcotest.(check bool)
        "external interruption cancels timer" false
        (Eio_mock.Clock.Mono.try_advance clock))

let zero_duration () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      let start = Eio.Time.Mono.now clock in
      check_result "zero duration cancels a waiting body" (Error `Timeout)
        (Timeout.timeout_mono ~clock Duration.zero (fun () -> Eio.Fiber.await_cancel ()));
      Alcotest.(check int64)
        "zero deadline does not advance time" 0L (elapsed_ns clock start))

let nested () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#mono_clock in
      List.iter
        (fun (outer, inner) ->
          let cleaned = ref false in
          let start = Eio.Time.Mono.now clock in
          let actual =
            Timeout.timeout_mono ~clock (Duration.ms outer) (fun () ->
                Timeout.timeout_mono ~clock (Duration.ms inner) (fun () ->
                    Eio.Switch.run (fun sw ->
                        Eio.Switch.on_release sw (fun () -> cleaned := true);
                        Eio.Fiber.await_cancel ())))
          in
          check_result "earlier nested deadline wins" (Error `Timeout) actual;
          Alcotest.(check int64) "minimum deadline" 10_000_000L (elapsed_ns clock start);
          Alcotest.(check bool) "nested callback cleanup awaited" true !cleaned;
          Alcotest.(check bool)
            "both nested timers removed" false
            (Eio_mock.Clock.Mono.try_advance clock))
        [ (10, 100); (100, 10) ])

let wall_jump wall_after () =
  Ox_test.run (fun env _ ->
      let clock = env#mono_clock in
      (* These clocks are distinct and owned by this backend. No machine clock
         changes, and no timer on the wall clock can expire the callback. *)
      Eio_mock.Clock.set_time env#clock 1_000.;
      Eio_mock.Clock.Mono.set_time clock (Mtime.of_uint64_ns 100_000_000_000L);
      Eio.Switch.run (fun sw ->
          let started, ready = Eio.Promise.create () in
          let pending =
            Eio.Fiber.fork_promise ~sw (fun () ->
                Timeout.timeout_mono ~clock (Duration.ms 100) (fun () ->
                    Eio.Promise.resolve ready ();
                    Eio.Fiber.await_cancel ()))
          in
          Eio.Promise.await started;
          Eio_mock.Clock.set_time env#clock wall_after;
          Eio.Fiber.yield ();
          Alcotest.(check bool)
            "wall correction does not settle monotonic timeout" true
            (Eio.Promise.peek pending = None);
          Eio_mock.Clock.Mono.set_time clock (Mtime.of_uint64_ns 100_099_000_000L);
          Eio.Fiber.yield ();
          Alcotest.(check bool)
            "still waiting before monotonic deadline" true
            (Eio.Promise.peek pending = None);
          Eio_mock.Clock.Mono.set_time clock (Mtime.of_uint64_ns 100_100_000_000L);
          check_result "settles at original monotonic deadline" (Error `Timeout)
            (Eio.Promise.await_exn pending);
          Alcotest.(check (float 0.))
            "wall time unchanged by timeout" wall_after (Eio.Time.now env#clock);
          Alcotest.(check bool)
            "no remaining monotonic timer" false
            (Eio_mock.Clock.Mono.try_advance clock)))

let tests =
  [
    ( "Monotonic timeout nmono-8jcy nmono-r2pk",
      [
        Alcotest.test_case "outcomes and timer cancellation" `Quick outcomes;
        Alcotest.test_case "deadline awaits child and switch cleanup" `Quick
          expiry_cleanup;
        Alcotest.test_case "callback and cleanup defects propagate" `Quick defects;
        Alcotest.test_case "caller switch ownership" `Quick caller_switch;
        Alcotest.test_case "external cancellation remains interruption" `Quick
          external_cancel;
        Alcotest.test_case "zero duration" `Quick zero_duration;
        Alcotest.test_case "nested deadlines" `Quick nested;
        Alcotest.test_case "wall-clock jump forward" `Quick (wall_jump 1_000_000.);
        Alcotest.test_case "wall-clock jump backward" `Quick (wall_jump (-1_000.));
      ] );
  ]
