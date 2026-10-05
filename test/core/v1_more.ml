open Ox

let check_int = Alcotest.(check int)
let check_bool = Alcotest.(check bool)
let check_float = Alcotest.(check (float 0.00001))

let schedule_variants () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let check name schedule expected_time =
        let start = Eio.Time.now clock and tries = ref 0 in
        let result =
          Retry.retry ~clock:env#mono_clock
            (Schedule.both (Schedule.recurs 3) schedule)
            (fun () ->
              incr tries;
              Error !tries)
        in
        check_bool (name ^ " terminal failure") true (result = Error 4);
        check_int (name ^ " attempts") 4 !tries;
        check_float (name ^ " virtual delays") expected_time (Eio.Time.now clock -. start)
      in
      check "retry uses fibonacci virtual delays"
        (Schedule.fibonacci (Duration.ms 10))
        0.04;
      check "retry uses windowed boundaries" (Schedule.windowed (Duration.ms 10)) 0.03;
      check "retry uses fixed cadence" (Schedule.fixed (Duration.ms 10)) 0.03;
      check "retry jittered schedule with fixed bounds"
        (Schedule.jittered ~random:(Random.State.make [| 1 |]) ~min:1. ~max:1.
           (Schedule.spaced (Duration.ms 10)))
        0.03;
      let seen = ref [] in
      let result =
        Retry.retry ~clock:env#mono_clock
          (Schedule.recur_until (function Error err -> err >= 1 | Ok _ -> false))
          (fun () ->
            let n = List.length !seen + 1 in
            seen := n :: !seen;
            Error n)
      in
      check_bool "retry passes typed failures to schedule" true (result = Error 1);
      check_int "retry stops when predicate rejects" 1 (List.length !seen))

let failure_schedules () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let successes = ref [] in
      let result =
        Retry.repeat ~clock:env#mono_clock
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.ms 3)))
          (fun () ->
            let n = List.length !successes + 1 in
            successes := n :: !successes;
            Ok n)
      in
      check_bool "repeat passes successful values to schedule" true (result = Ok (2, 2));
      check_int "repeat schedule" 3 (List.length !successes);
      let tries = ref 0 in
      let result =
        Scope.run (fun _ ->
            Timeout.timeout ~clock (Duration.ms 12) (fun () ->
                Retry.retry ~clock:env#mono_clock
                  (Schedule.spaced (Duration.ms 10))
                  (fun () ->
                    incr tries;
                    Error `Again)))
      in
      (match result with
      | Exit.Failure (Cause.Fail `Timeout) -> ()
      | _ -> Alcotest.fail "retry timeout interrupts loop");
      check_int "retry does not run after deadline" 2 !tries;
      tries := 0;
      (match
         Scope.run (fun _ ->
             Retry.retry ~clock:env#mono_clock (Schedule.recurs 5) (fun () ->
                 incr tries;
                 raise (Eio.Cancel.Cancelled (Failure "external"))))
       with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "retry does not retry interrupt");
      check_int "retry does not retry cancellation" 1 !tries)

let background_cases () =
  Eio_main.run (fun _ ->
      let cleaned = ref 0 in
      let pending () =
        Fun.protect
          (fun () -> Eio.Fiber.await_cancel ())
          ~finally:(fun () -> incr cleaned)
      in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw pending (fun () ->
                 Eio.Fiber.yield ();
                 Ok 7))
       with
      | Exit.Success 7 -> ()
      | _ -> Alcotest.fail "body success");
      check_int "with_background body success or failure cancels and awaits child" 1
        !cleaned;
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw pending (fun () ->
                 Eio.Fiber.yield ();
                 Error "plain-body"))
       with
      | Exit.Failure (Cause.Fail "plain-body") ->
          check_int
            "with_background body-first keeps the body exit for plain, named,  \
             observability-named, and traced backgrounds"
            2 !cleaned
      | _ -> Alcotest.fail "plain background body-first failure lost");
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw pending (fun () ->
                 Eio.Fiber.yield ();
                 failwith "body defect"))
       with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "body defect");
      check_int "background cleanup after body defect" 3 !cleaned;
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw
               (fun () ->
                 Eio.Fiber.yield ();
                 failwith "background defect")
               pending)
       with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "background defect");
      check_int "with_background defect cancels use and awaits finalizers" 4 !cleaned;
      match
        Scope.run (fun sw ->
            Concurrent.with_background ~sw
              (fun () ->
                Fun.protect
                  (fun () -> Eio.Fiber.await_cancel ())
                  ~finally:(fun () -> failwith "cleanup defect"))
              (fun () ->
                Eio.Fiber.yield ();
                Error "body"))
      with
      | Exit.Failure (Cause.Die (ex, _)) ->
          let text = Printexc.to_string ex in
          check_bool "cleanup defect remains visible" true
            (String.starts_with ~prefix:"Fun.Finally_raised: Failure(\"cleanup defect\")"
               text)
      | Exit.Failure cause ->
          Alcotest.failf "background finalizer shape: %a"
            (Cause.pp Format.pp_print_string)
            cause
      | Exit.Success _ -> Alcotest.fail "background finalizer was lost")

let tests =
  [
    ( "v1 retry schedule variants ^nport-rry6",
      [
        Alcotest.test_case "fibonacci, windowed, fixed, jitter and predicate" `Quick
          schedule_variants;
        Alcotest.test_case "repeat, timeout and interruption" `Quick failure_schedules;
      ] );
    ( "v1 background variants ^nport-ivyn",
      [
        Alcotest.test_case "body and background defects, release visibility" `Quick
          background_cases;
      ] );
  ]
