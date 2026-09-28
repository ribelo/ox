(* v1 behavioural ports: ^nport-v4oy ^nport-bo4a ^nport-rry6
   ^nport-ivyn ^nport-kaym ^nport-ozuw. Scenarios from the v1
   core_common suites, rewritten over Eio switches and direct-style results. *)
open Eta

let check_int label expected actual = Alcotest.(check int) label expected actual
let check_bool label expected actual = Alcotest.(check bool) label expected actual
let check_string label expected actual = Alcotest.(check string) label expected actual
let render cause = Format.asprintf "%a" (Cause.pp_compact Format.pp_print_string) cause
let backtrace () = Printexc.get_callstack 1

let cause_exit () =
  let id = Interrupt_id.create () in
  let fail = Cause.Fail "typed" and interrupt = Cause.Interrupt (Some id) in
  let defect = Cause.Die (Failure "bad", backtrace ()) in
  let combined = Cause.Concurrent [ fail; interrupt; defect ] in
  check_string "cause compact corpus"
    ("Concurrent[Fail(typed); Interrupt(" ^ Interrupt_id.to_string id
   ^ "); Die(Failure(\"bad\"))]")
    (render combined);
  check_bool "mixed cause not pure interruption" false (Cause.is_interrupt_only combined);
  (* ncore-k6az, pulled by Pie pienext: every typed failure, depth first *)
  check_bool "failures in order" true
    (Cause.failures
       (Cause.Concurrent
          [
            Cause.Suppressed
              { primary = Cause.Fail 1; finalizer = Cause.Finalizer (Cause.Fail 2) };
            Cause.Die (Exit, Printexc.get_callstack 1);
            Cause.Interrupt None;
            Cause.Fail 3;
          ])
    = [ 1; 2; 3 ]);
  check_bool "interrupt-only concurrent" true
    (Cause.is_interrupt_only (Cause.Concurrent [ interrupt; Cause.Interrupt None ]));
  check_bool "empty concurrent is not an interrupt" false
    (Cause.is_interrupt_only (Cause.Concurrent []));
  check_int "interrupt process code" 130 (Exit.process_code (Exit.Failure interrupt));
  check_int "combinators" 1 (Exit.process_code (Exit.Failure combined));
  check_int "success process code" 0 (Exit.process_code (Exit.Success 3));
  (match Exit.to_result (Exit.Failure fail) with
  | Ok (Error "typed") -> ()
  | _ -> Alcotest.fail "extractors and squash");
  (match Exit.to_result (Exit.Failure combined) with
  | Error _ -> ()
  | _ -> Alcotest.fail "composite cause projected as typed error");
  let suppressed = Cause.Suppressed { primary = fail; finalizer = defect } in
  check_string "suppressed compact corpus"
    "Suppressed(Fail(typed); Die(Failure(\"bad\")))" (render suppressed);
  check_string "nested finalizer compact corpus" "Finalizer(Die(Failure(\"bad\")))"
    (render (Cause.Finalizer defect));
  check_bool "suppressed not interrupt only" false (Cause.is_interrupt_only suppressed)

let release_laws () =
  Eio_main.run (fun _ ->
      let events = ref [] in
      let add value = events := value :: !events in
      (match
         Scope.run (fun sw ->
             let acquire n =
               Resource.acquire_release ~sw
                 ~acquire:(fun () -> Ok n)
                 ~release:(fun n -> add ("release" ^ string_of_int n))
             in
             ignore (acquire 1);
             ignore (acquire 2);
             add "body";
             Ok 7)
       with
      | Exit.Success 7 -> ()
      | _ -> Alcotest.fail "success release result");
      Alcotest.(check (list string))
        "acquire release finalizers lifo sequential"
        [ "release1"; "release2"; "body" ]
        !events;
      events := [];
      (match
         Scope.run (fun sw ->
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Error "acquire")
                  ~release:(fun _ -> add "released"));
             Error "acquire")
       with
      | Exit.Failure (Cause.Fail "acquire") -> ()
      | _ -> Alcotest.fail "acquisition failure");
      Alcotest.(check (list string)) "failed acquire has no release" [] !events;
      (match
         Scope.run (fun sw ->
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok ())
                  ~release:(fun () -> add "released"));
             Error "body")
       with
      | Exit.Failure (Cause.Fail "body") -> ()
      | _ -> Alcotest.fail "typed body failure");
      Alcotest.(check (list string)) "acquire release on failure" [ "released" ] !events;
      events := [];
      (match
         Scope.run (fun sw ->
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok ())
                  ~release:(fun () -> add "released"));
             failwith "body")
       with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "body defect");
      Alcotest.(check (list string))
        "acquire release releases on defect" [ "released" ] !events;
      events := [];
      (match
         Scope.run (fun sw ->
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok 1)
                  ~release:(fun _ -> add "first"));
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok 2)
                  ~release:(fun _ ->
                    add "second";
                    failwith "cleanup"));
             Error "body")
       with
      | Exit.Failure
          (Cause.Suppressed
             { primary = Cause.Fail "body"; finalizer = Cause.Die (Failure _, _) }) ->
          ()
      | _ -> Alcotest.fail "acquire release suppresses release failure");
      Alcotest.(check (list string))
        "acquire release finalizer failure keeps running" [ "first"; "second" ] !events)

let timeout_laws () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let start = Eio.Time.now clock in
      let seen = ref [] in
      let result =
        Timeout.timeout ~clock (Duration.ms 25) (fun () ->
            Eio.Switch.run (fun sw ->
                Eio.Switch.on_release sw (fun () -> seen := "release" :: !seen);
                Eio.Time.sleep clock 10.;
                Ok 1))
      in
      check_bool "timeout uses virtual clock" true (result = Error `Timeout);
      Alcotest.(check (list string)) "release settled before timeout" [ "release" ] !seen;
      Alcotest.(check (float 0.00001)) "virtual time" 0.025 (Eio.Time.now clock -. start);
      let result = Timeout.timeout ~clock (Duration.ms 25) (fun () -> Ok 2) in
      check_bool "timeout allows fast success" true (result = Ok 2);
      let result = Timeout.timeout ~clock (Duration.ms 25) (fun () -> Error `Timeout) in
      check_bool "timeout preserves user timeout failure" true (result = Error `Timeout);
      let result = Timeout.timeout ~clock (Duration.ms 25) (fun () -> Error `Other) in
      check_bool "body failure unchanged" true (result = Error `Other))

let retry_repeat_laws () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock and calls = ref 0 in
      let attempt () =
        incr calls;
        if !calls < 3 then Error !calls else Ok 9
      in
      let start = Eio.Time.now clock in
      check_bool "retry schedule until success" true
        (Retry.retry ~clock (Schedule.spaced (Duration.ms 10)) attempt = Ok 9);
      check_int "one initial plus two retries" 3 !calls;
      Alcotest.(check (float 0.00001)) "virtual retries" 0.02 (Eio.Time.now clock -. start);
      calls := 0;
      check_bool "retry does nothing on initial success" true
        (Retry.retry ~clock (Schedule.recurs 5) (fun () ->
             incr calls;
             Ok 8)
        = Ok 8);
      check_int "initial success one call" 1 !calls;
      calls := 0;
      check_bool "terminal failure retained" true
        (Retry.retry ~clock (Schedule.recurs 2) (fun () ->
             incr calls;
             Error !calls)
        = Error 3);
      check_int "retry attempts can be observed without schedule taps" 3 !calls;
      calls := 0;
      let fail_once () =
        incr calls;
        if !calls = 2 then Error "stop" else Ok !calls
      in
      check_bool "repeat stops on failure" true
        (Retry.repeat ~clock (Schedule.recurs 5) fail_once = Error "stop");
      check_int "no further repeats" 2 !calls;
      calls := 0;
      check_bool "repeat recurs zero runs body once" true
        (Retry.repeat ~clock (Schedule.recurs 0) (fun () ->
             incr calls;
             Ok !calls)
        = Ok 0);
      check_int "one body for recurs zero" 1 !calls;
      calls := 0;
      let start = Eio.Time.now clock in
      check_bool "successful values drive schedule" true
        (Retry.repeat ~clock
           (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.ms 5)))
           (fun () ->
             incr calls;
             Ok !calls)
        = Ok (2, 2));
      check_int "two continuations" 3 !calls;
      Alcotest.(check (float 0.00001))
        "repeat schedule uses virtual delays" 0.01
        (Eio.Time.now clock -. start);
      (match
         Scope.run (fun _ ->
             Retry.retry ~clock (Schedule.recurs 3) (fun () ->
                 incr calls;
                 failwith "defect"))
       with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "retry does not catch defects");
      check_int "defect not retried" 4 !calls)

let supervisor_laws () =
  Eio_main.run (fun _ ->
      let alive = ref 0 and cleaned = ref 0 in
      let blocked () =
        incr alive;
        Fun.protect
          (fun () -> Eio.Fiber.await_cancel ())
          ~finally:(fun () ->
            decr alive;
            incr cleaned)
      in
      let outcome =
        Scope.run (fun sw ->
            match
              Concurrent.with_background ~sw blocked (fun () ->
                  Eio.Fiber.yield ();
                  Error "body")
            with
            | Error "body" -> Error "body"
            | _ -> Alcotest.fail "body winner")
      in
      (match outcome with
      | Exit.Failure (Cause.Fail "body") -> ()
      | _ -> Alcotest.fail "own stop obscured typed body error");
      check_int "background physically exited" 0 !alive;
      check_int "background cleanup awaited" 1 !cleaned;
      let outcome =
        Scope.run (fun sw ->
            Concurrent.with_background ~sw
              (fun () ->
                Eio.Fiber.yield ();
                Error "background")
              blocked)
      in
      (match outcome with
      | Exit.Failure (Cause.Fail "background") -> ()
      | _ -> Alcotest.fail "background typed failure did not win");
      check_int "body physically exited" 0 !alive;
      check_int "with_background typed failure cancels use and awaits finalizers" 2
        !cleaned;
      (match
         Scope.run (fun sw -> Concurrent.par ~sw (fun () -> Error "left") blocked)
       with
      | Exit.Failure (Cause.Fail "left") -> ()
      | _ -> Alcotest.fail "par failure lost");
      check_int "par loser exited" 0 !alive;
      let result =
        Scope.run (fun sw ->
            Concurrent.race ~sw [ (fun () -> Error "first"); (fun () -> Ok 42) ])
      in
      (match result with
      | Exit.Success 42 -> ()
      | Exit.Failure cause ->
          Alcotest.failf "race failure: %a"
            (Cause.pp (Cause.pp Format.pp_print_string))
            cause
      | Exit.Success _ -> Alcotest.fail "race returned unexpected success");
      let result =
        Scope.run (fun sw ->
            Concurrent.race ~sw [ (fun () -> Error "first"); (fun () -> Error "second") ])
      in
      match result with
      | Exit.Failure
          (Cause.Fail (Cause.Concurrent [ Cause.Fail "first"; Cause.Fail "second" ])) ->
          ()
      | _ -> Alcotest.fail "race must retain all failures in input order")

let cancellation_laws () =
  Eio_main.run (fun _ ->
      let released = ref false and exited = ref false in
      let outcome =
        Eio.Cancel.sub (fun ctx ->
            Eio.Switch.run (fun outer ->
                Eio.Fiber.fork ~sw:outer (fun () ->
                    Eio.Fiber.yield ();
                    Eio.Cancel.cancel ctx (Failure "external"));
                Scope.run (fun sw ->
                    ignore
                      (Resource.acquire_release ~sw
                         ~acquire:(fun () -> Ok ())
                         ~release:(fun () -> released := true));
                    Fun.protect
                      (fun () -> Eio.Fiber.await_cancel ())
                      ~finally:(fun () -> exited := true))))
      in
      (match outcome with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "external cancellation classification");
      check_bool "acquire_use_release releases on cancel" true !released;
      check_bool "nested body physically exited" true !exited)

let stress_laws () =
  Eio_main.run (fun _ ->
      let random = Random.State.make [| 0x5eed |] in
      for n = 1 to 16 do
        let live = ref 0 and released = ref 0 in
        let result =
          Scope.run (fun sw ->
              Concurrent.all ~sw
                (List.init n (fun i () ->
                     if Random.State.bool random then Eio.Fiber.yield ();
                     match
                       Resource.acquire_release ~sw
                         ~acquire:(fun () ->
                           incr live;
                           Ok i)
                         ~release:(fun _ ->
                           decr live;
                           incr released)
                     with
                     | Ok value -> Ok value
                     | Error e -> Error e)))
        in
        (match result with
        | Exit.Success values -> check_int "all results" n (List.length values)
        | _ -> Alcotest.fail "all stress result");
        check_int "randomized all compositions release" 0 !live;
        check_int "every resource released" n !released
      done;
      for _ = 1 to 24 do
        let live = ref 0 in
        let result =
          Scope.run (fun sw ->
              Concurrent.race ~sw
                [
                  (fun () ->
                    incr live;
                    Fun.protect
                      (fun () -> Eio.Fiber.await_cancel ())
                      ~finally:(fun () -> decr live));
                  (fun () ->
                    if Random.State.bool random then Eio.Fiber.yield ();
                    Ok 1);
                ])
        in
        (match result with
        | Exit.Success 1 -> ()
        | _ -> Alcotest.fail "race stress winner");
        check_int "randomized race compositions release" 0 !live
      done)

(* The v1 corpus cases are separate assertions, not copies of the old grammar:
   eta-next renders a smaller Cause tree without captured typed finalizer payloads. *)
let cause_render_corpus () =
  let fail text = Cause.Fail text in
  let die = Cause.Die (Failure "boom", backtrace ()) in
  let compact label expected cause = check_string label expected (render cause) in
  compact "corpus concurrent fail+interrupt" "Concurrent[Fail(a); Interrupt(external)]"
    (Cause.Concurrent [ fail "a"; Cause.Interrupt None ]);
  compact "corpus suppressed fail+die" "Suppressed(Fail(a); Die(Failure(\"boom\")))"
    (Cause.Suppressed { primary = fail "a"; finalizer = die });
  compact "corpus nested finalizer sequential" "Finalizer(Concurrent[Fail(a); Fail(b)])"
    (Cause.Finalizer (Cause.Concurrent [ fail "a"; fail "b" ]));
  let id = Interrupt_id.create () in
  compact "corpus interrupts anonymous vs identified"
    ("Concurrent[Interrupt(external); Interrupt(" ^ Interrupt_id.to_string id ^ ")]")
    (Cause.Concurrent [ Cause.Interrupt None; Cause.Interrupt (Some id) ]);
  compact "corpus leaf cannot counterfeit composite" "Fail(Concurrent[Fail(x)])"
    (fail "Concurrent[Fail(x)]");
  compact "corpus multi-defect composite"
    "Concurrent[Die(Failure(\"boom\")); Die(Failure(\"boom\"))]"
    (Cause.Concurrent [ die; die ]);
  compact "corpus suppressed x concurrent x finalizer"
    "Suppressed(Concurrent[Fail(a); Fail(b)]; Finalizer(Die(Failure(\"boom\"))))"
    (Cause.Suppressed
       {
         primary = Cause.Concurrent [ fail "a"; fail "b" ];
         finalizer = Cause.Finalizer die;
       });
  compact "corpus mixed nesting parenthesizes" "Finalizer(Suppressed(Fail(a); Fail(b)))"
    (Cause.Finalizer (Cause.Suppressed { primary = fail "a"; finalizer = fail "b" }));
  compact "corpus suppressed primary suppressed"
    "Suppressed(Suppressed(Fail(a); Fail(b)); Die(Failure(\"boom\")))"
    (Cause.Suppressed
       {
         primary = Cause.Suppressed { primary = fail "a"; finalizer = fail "b" };
         finalizer = die;
       });
  compact "corpus empty and singleton raw composites" "Concurrent[]" (Cause.Concurrent []);
  compact "corpus singleton raw composite" "Concurrent[Fail(a)]"
    (Cause.Concurrent [ fail "a" ]);
  check_bool "corpus newline sanitization" false
    (String.contains (render (fail "line\nbreak")) '\n');
  check_bool "compact newline-freedom property" false
    (String.contains
       (render (Cause.Concurrent [ fail "typed\nvalue"; Cause.Interrupt None ]))
       '\n');
  check_bool "pretty stays multi-line on Die backtrace" true
    (String.contains (Format.asprintf "%a" (Cause.pp Format.pp_print_string) die) '\n')

let resource_repeat () =
  Eio_mock.Backend.run_full (fun env ->
      let acquired = ref 0 and released = ref 0 in
      (match
         Scope.run (fun _ ->
             Retry.repeat ~clock:env#clock (Schedule.recurs 3) (fun () ->
                 incr acquired;
                 Scope.run (fun inner ->
                     ignore
                       (Resource.acquire_release ~sw:inner
                          ~acquire:(fun () -> Ok ())
                          ~release:(fun () -> incr released));
                     Ok ())
                 |> function
                 | Exit.Success () -> Ok ()
                 | _ -> Alcotest.fail "repeat iteration scope failed"))
       with
      | Exit.Success 3 -> ()
      | _ -> Alcotest.fail "repeat output");
      check_int "repeat releases resources each iteration" 4 !released;
      check_int "repeat acquires resources each iteration" !acquired !released;
      let lifo = ref [] in
      (match
         Scope.run (fun sw ->
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok 1)
                  ~release:(fun n -> lifo := n :: !lifo));
             ignore
               (Resource.acquire_release ~sw
                  ~acquire:(fun () -> Ok 2)
                  ~release:(fun n -> lifo := n :: !lifo));
             Ok ())
       with
      | Exit.Success () -> ()
      | _ -> Alcotest.fail "finalizer scope");
      Alcotest.(check (list int)) "finalizers run lifo sequentially" [ 1; 2 ] !lifo)

let nested_timeouts () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock and cleanup = ref false in
      let result =
        Timeout.timeout ~clock (Duration.ms 10) (fun () ->
            Timeout.timeout ~clock (Duration.ms 40) (fun () ->
                Fun.protect
                  (fun () ->
                    Eio.Time.sleep clock 1.;
                    Ok 1)
                  ~finally:(fun () -> cleanup := true)))
      in
      check_bool "nested timeout maps outer timeout" true (result = Error `Timeout);
      check_bool "nested timeout preserves externally cancelled cleanup" true !cleanup;
      let calls = ref 0 in
      (match
         Scope.run (fun sw ->
             Timeout.timeout ~clock (Duration.ms 10) (fun () ->
                 ignore
                   (Resource.acquire_release ~sw
                      ~acquire:(fun () -> Ok ())
                      ~release:(fun () -> incr calls));
                 Eio.Time.sleep clock 1.;
                 Ok ()))
       with
      | Exit.Failure (Cause.Fail `Timeout) -> ()
      | _ -> Alcotest.fail "deadline within owning scope");
      check_int "timeout release exactly once" 1 !calls)

let retry_bounds () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock and calls = ref 0 in
      let attempt () =
        incr calls;
        Error !calls
      in
      let start = Eio.Time.now clock in
      let result =
        Retry.retry ~clock
          (Schedule.both (Schedule.recurs 3) (Schedule.spaced (Duration.ms 7)))
          attempt
      in
      check_bool "retry recurs attempts initial plus retries" true (result = Error 4);
      check_int "retry schedule uses virtual delays" 4 !calls;
      Alcotest.(check (float 0.00001))
        "retry delayed 3 times" 0.021
        (Eio.Time.now clock -. start);
      ())

let tests =
  [
    ( "v1 cause/exit/render ^nport-v4oy",
      [
        Alcotest.test_case "classification and compact corpus" `Quick cause_exit;
        Alcotest.test_case "v1 13-case rendering corpus" `Quick cause_render_corpus;
      ] );
    ( "v1 resource/timeout ^nport-bo4a ^nport-kaym",
      [
        Alcotest.test_case "LIFO acquisition, failure and suppression" `Quick release_laws;
        Alcotest.test_case "virtual deadline and release" `Quick timeout_laws;
        Alcotest.test_case "external cancellation releases" `Quick cancellation_laws;
        Alcotest.test_case "repeat resource lifetimes" `Quick resource_repeat;
        Alcotest.test_case "nested deadline and cleanup" `Quick nested_timeouts;
      ] );
    ( "v1 retry/repeat ^nport-rry6",
      [
        Alcotest.test_case "schedule-driven outcomes" `Quick retry_repeat_laws;
        Alcotest.test_case "virtual retry schedule bounds" `Quick retry_bounds;
      ] );
    ( "v1 supervisor ^nport-ivyn",
      [
        Alcotest.test_case "background par race physically exited" `Quick supervisor_laws;
      ] );
    ( "v1 stress ^nport-ozuw",
      [ Alcotest.test_case "bounded resource and race iterations" `Quick stress_laws ] );
  ]
