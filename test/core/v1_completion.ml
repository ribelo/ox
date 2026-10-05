(* ^safe-1bc7 ^safe-xls8: Assert scripted outcomes instead of discarding results;
   lifetime, cancellation and failure observations remain independently checked. *)
open Ox

let check_int = Alcotest.(check int)
let check_bool = Alcotest.(check bool)
let check_float = Alcotest.(check (float 0.00001))

let clock_cases () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let start = Eio.Time.now clock in
      Eio.Time.sleep clock 0.;
      check_float "sleep without wall time" start (Eio.Time.now clock);
      Eio.Time.sleep clock 0.013;
      check_float "sleep delays until adjusted" 0.013 (Eio.Time.now clock -. start);
      let completed = ref [] in
      Eio.Switch.run (fun sw ->
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.sleep clock 0.03;
              completed := 30 :: !completed);
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.sleep clock 0.01;
              completed := 10 :: !completed));
      Alcotest.(check (list int)) "multiple sleeps" [ 30; 10 ] !completed;
      check_float "set_time wakes due sleepers (auto-advance mock)" 0.043
        (Eio.Time.now clock -. start))

let retry_resource_cases () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock and released = ref 0 and attempts = ref 0 in
      let outcome =
        Retry.retry ~clock:env#mono_clock (Schedule.recurs 2) (fun () ->
            incr attempts;
            match
              Scope.run (fun sw ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw
                       ~acquire:(fun () -> Ok ())
                       ~release:(fun () -> incr released)
                    = Ok ());
                  if !attempts < 3 then Error !attempts else Ok !attempts)
            with
            | Exit.Success n -> Ok n
            | Exit.Failure (Cause.Fail n) -> Error n
            | _ -> Alcotest.fail "retry attempt caused a defect")
      in
      check_bool "retry releases resources each failed attempt" true (outcome = Ok 3);
      check_int "retry releases resources on success too" 3 !released;
      let values = ref [] in
      let stopped =
        Retry.repeat ~clock:env#mono_clock
          (Schedule.both (Schedule.recurs 7) (Schedule.spaced (Duration.ms 5)))
          (fun () ->
            let next = List.length !values + 1 in
            values := next :: !values;
            if next = 3 then Error "halt" else Ok next)
      in
      check_bool "repeat stops on typed failure" true (stopped = Error "halt");
      check_int "repeat stops before fourth iteration" 3 (List.length !values);
      attempts := 0;
      let result =
        Scope.run (fun _ ->
            Timeout.timeout ~clock (Duration.ms 13) (fun () ->
                Retry.repeat ~clock:env#mono_clock
                  (Schedule.spaced (Duration.ms 10))
                  (fun () ->
                    incr attempts;
                    Ok !attempts)))
      in
      (match result with
      | Exit.Failure (Cause.Fail `Timeout) -> ()
      | _ -> Alcotest.fail "repeat timeout interrupts loop");
      check_int "repeat timeout does not run third body" 2 !attempts)

let stress_compositions () =
  Eio_main.run (fun _ ->
      for size = 1 to 30 do
        let live = ref 0 and acquired = ref 0 and released = ref 0 in
        let worker sw n () =
          Eio.Switch.run (fun nested ->
              check_bool "scripted resource acquisition succeeds" true
                (Support.acquire_release ~sw:nested
                   ~acquire:(fun () ->
                     incr live;
                     incr acquired;
                     Ok ())
                   ~release:(fun () ->
                     decr live;
                     incr released)
                = Ok ());
              Eio.Fiber.yield ();
              if n > 0 && n mod 7 = 0 then Error n else Ok n)
        in
        let result =
          Scope.run (fun sw -> Concurrent.all ~sw (List.init size (worker sw)))
        in
        (if size >= 8 then
           match result with
           | Exit.Failure (Cause.Fail _) -> ()
           | _ -> Alcotest.fail "par scoped resource released on failure"
         else
           match result with
           | Exit.Success values ->
               check_int "all preserves admitted result count" size (List.length values)
           | _ -> Alcotest.fail "par result");
        check_int "nested scope catch retry releases all" 0 !live;
        check_int "all without scoped releases at scope exit" !acquired !released
      done)

let bracket_cases () =
  Eio_main.run (fun _ ->
      let events = ref [] in
      let resource sw =
        Support.acquire_release ~sw
          ~acquire:(fun () -> Ok 4)
          ~release:(fun value -> events := value :: !events)
      in
      (match
         Scope.run (fun sw ->
             match resource sw with
             | Ok value -> Ok (value + 1)
             | Error error -> Error error)
       with
      | Exit.Success 5 -> ()
      | _ -> Alcotest.fail "acquire_use_release success");
      Alcotest.(check (list int)) "acquire_use_release lexical bracket" [ 4 ] !events;
      events := [];
      (match
         Scope.run (fun sw ->
             check_bool "scripted resource acquisition succeeds" true (resource sw = Ok 4);
             Error "body")
       with
      | Exit.Failure (Cause.Fail "body") -> ()
      | _ -> Alcotest.fail "acquire_use_release typed failure");
      Alcotest.(check (list int))
        "acquire_use_release typed failure releases" [ 4 ] !events;
      events := [];
      (match
         Scope.run (fun sw ->
             check_bool "scripted resource acquisition succeeds" true (resource sw = Ok 4);
             failwith "body defect")
       with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "acquire_use_release defect releases");
      Alcotest.(check (list int)) "acquire_use_release defect release" [ 4 ] !events;
      let outcome =
        Scope.run (fun sw ->
            check_bool "scripted resource acquisition succeeds" true
              (Support.acquire_release ~sw
                 ~acquire:(fun () -> Ok ())
                 ~release:(fun () -> failwith "release after success")
              = Ok ());
            Ok ())
      in
      (match outcome with
      | Exit.Failure (Cause.Finalizer (Cause.Die (Failure _, _))) -> ()
      | _ -> Alcotest.fail "acquire release release failure after success");
      let bracket_release =
        Scope.run (fun sw ->
            check_bool "scripted resource acquisition succeeds" true
              (Support.acquire_release ~sw
                 ~acquire:(fun () -> Ok ())
                 ~release:(fun () -> failwith "bracket release after success")
              = Ok ());
            Ok ())
      in
      match bracket_release with
      | Exit.Failure (Cause.Finalizer (Cause.Die (Failure _, _))) -> ()
      | _ -> Alcotest.fail "acquire_use_release release failure after success")

let parallel_resource_cases () =
  Eio_main.run (fun _ ->
      for size = 2 to 16 do
        let live = ref 0 and releases = ref [] in
        let result =
          Scope.run (fun sw ->
              Concurrent.all ~sw
                (List.init size (fun n () ->
                     match
                       Support.acquire_release ~sw
                         ~acquire:(fun () ->
                           incr live;
                           Ok n)
                         ~release:(fun value ->
                           decr live;
                           releases := value :: !releases)
                     with
                     | Error error -> Error error
                     | Ok value ->
                         Eio.Fiber.yield ();
                         if value = size - 1 then Error value else Ok value)))
        in
        (match result with
        | Exit.Failure (Cause.Fail n) when n = size - 1 -> ()
        | _ -> Alcotest.fail "acquire_all_par failure reverse cleanup");
        check_int "acquire_all_par scope exit ownership" 0 !live;
        check_int "acquire_all_par rollback releases admitted resources" size
          (List.length !releases);
        Alcotest.(check (list int))
          "acquire_all_par failure reverse cleanup" (List.init size Fun.id) !releases
      done;
      let called = ref [] in
      (match
         Scope.run (fun sw ->
             Concurrent.all ~sw
               [
                 (fun () ->
                   called := 1 :: !called;
                   Ok 1);
                 (fun () ->
                   called := 2 :: !called;
                   Ok 2);
                 (fun () ->
                   called := 3 :: !called;
                   Ok 3);
               ])
       with
      | Exit.Success [ 1; 2; 3 ] -> ()
      | _ -> Alcotest.fail "acquire_all_par input order");
      check_int "acquire_all_par admission and concurrency" 3 (List.length !called))

let concurrent_cases () =
  Eio_main.run (fun _ ->
      let finalized = ref 0 in
      let pending () =
        Fun.protect
          (fun () -> Eio.Fiber.await_cancel ())
          ~finally:(fun () -> incr finalized)
      in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw pending (fun () ->
                 Concurrent.par ~sw
                   (fun () -> Error "body")
                   (fun () -> Eio.Fiber.await_cancel ())))
       with
      | Exit.Failure (Cause.Fail "body") -> ()
      | _ -> Alcotest.fail "with_background nested par typed body failure preserved");
      check_int "with_background nested par own-stop awaits cleanup" 1 !finalized;
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw pending (fun () ->
                 Concurrent.race ~sw
                   [
                     (fun () -> Error "early");
                     (fun () ->
                       Eio.Fiber.yield ();
                       Ok 42);
                   ]))
       with
      | Exit.Success 42 -> ()
      | _ -> Alcotest.fail "with_background nested race winner preserved");
      check_int "nested background physically exited" 2 !finalized;
      let exited = ref 0 in
      (match
         Scope.run (fun sw ->
             Concurrent.par ~sw
               (fun () ->
                 Eio.Fiber.yield ();
                 Error "stop")
               (fun () ->
                 Fun.protect
                   (fun () -> Eio.Fiber.await_cancel ())
                   ~finally:(fun () -> incr exited)))
       with
      | Exit.Failure (Cause.Fail "stop") -> ()
      | _ -> Alcotest.fail "par scoped resource released on failure");
      check_int "par loser finalizer visible after return" 1 !exited;
      let alive = ref 0 in
      let result =
        Scope.run (fun sw ->
            Concurrent.race ~sw
              (List.init 12 (fun _ () ->
                   incr alive;
                   Fun.protect
                     (fun () -> Eio.Fiber.await_cancel ())
                     ~finally:(fun () -> decr alive))
              @ [
                  (fun () ->
                    Eio.Fiber.yield ();
                    Ok 5);
                ]))
      in
      (match result with
      | Exit.Success 5 -> ()
      | _ -> Alcotest.fail "race many branches resource cleanup");
      check_int "nested fibers physically exited" 0 !alive)

let cadence_cases () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let start = Eio.Time.now clock and attempts = ref 0 in
      let outcome =
        Retry.repeat ~clock:env#mono_clock
          (Schedule.both (Schedule.recurs 2) (Schedule.fixed (Duration.ms 10)))
          (fun () ->
            incr attempts;
            Eio.Time.sleep clock 0.02;
            Ok !attempts)
      in
      (match outcome with
      | Ok (2, _) -> ()
      | _ -> Alcotest.fail "repeat fixed cadence differs from spaced");
      check_int "repeat fixed overrun iterations" 3 !attempts;
      let fixed_elapsed = Eio.Time.now clock -. start in
      check_float "repeat fixed overrun has no pileup" 0.07 fixed_elapsed;
      let spaced_start = Eio.Time.now clock in
      let spaced =
        Retry.repeat ~clock:env#mono_clock
          (Schedule.both (Schedule.recurs 2) (Schedule.spaced (Duration.ms 10)))
          (fun () ->
            Eio.Time.sleep clock 0.02;
            Ok 1)
      in
      (match spaced with
      | Ok (2, _) -> ()
      | _ -> Alcotest.fail "spaced repeat exhausted unexpectedly");
      check_bool "repeat fixed cadence differs from spaced" true
        (Eio.Time.now clock -. spaced_start > fixed_elapsed);
      let start = Eio.Time.now clock in
      attempts := 0;
      let outcome =
        Retry.retry ~clock:env#mono_clock
          (Schedule.both
             (Schedule.during (Duration.ms 12))
             (Schedule.spaced (Duration.ms 10)))
          (fun () ->
            incr attempts;
            Error !attempts)
      in
      check_bool "retry during schedule bounds elapsed" true (outcome = Error 3);
      check_float "retry during bounds virtual elapsed" 0.02 (Eio.Time.now clock -. start);
      let start = Eio.Time.now clock in
      attempts := 0;
      let result =
        Retry.retry ~clock:env#mono_clock
          (Schedule.both (Schedule.recurs 4)
             (Schedule.jittered ~random:(Random.State.make [| 1 |]) ~min:0.5 ~max:1.5
                (Schedule.spaced (Duration.ms 10))))
          (fun () ->
            incr attempts;
            Error !attempts)
      in
      let elapsed = Eio.Time.now clock -. start in
      check_bool "retry jittered schedule stays inside the supplied range" true
        (result = Error 5 && !attempts = 5 && elapsed >= 0.02 && elapsed <= 0.06))

let resource_edge_cases () =
  Eio_main.run (fun env ->
      let released = ref [] in
      let outcome =
        Scope.run (fun sw ->
            check_bool "scripted resource acquisition succeeds" true
              (Support.acquire_release ~sw
                 ~acquire:(fun () -> Ok 1)
                 ~release:(fun value -> released := value :: !released)
              = Ok 1);
            Ok 1)
      in
      check_bool "acquire release root finalizer" true
        (outcome = Exit.Success 1 && !released = [ 1 ]);
      released := [];
      let outcome =
        Scope.run (fun sw ->
            check_bool "scripted resource acquisition succeeds" true
              (Support.acquire_release ~sw
                 ~acquire:(fun () -> Ok 2)
                 ~release:(fun value -> released := value :: !released)
              = Ok 2);
            Error "root")
      in
      check_bool "acquire release root failure finalizer" true
        (outcome = Exit.Failure (Cause.Fail "root") && !released = [ 2 ]);
      (match
         Scope.run (fun sw ->
             check_bool "scripted resource acquisition succeeds" true
               (Support.acquire_release ~sw
                  ~acquire:(fun () -> Ok ())
                  ~release:(fun () -> failwith "release after body defect")
               = Ok ());
             failwith "body defect")
       with
      | Exit.Failure
          (Cause.Suppressed
             {
               primary = Cause.Die (Failure body, _);
               finalizer = Cause.Die (Failure release, _);
             }) ->
          check_bool "acquire release suppresses release failure after defect" true
            (body = "body defect" && release = "release after body defect")
      | _ -> Alcotest.fail "acquire release suppresses release failure after defect");
      (match
         Scope.run (fun sw ->
             check_bool "scripted resource acquisition succeeds" true
               (Support.acquire_release ~sw
                  ~acquire:(fun () -> Ok ())
                  ~release:(fun () -> failwith "bracket release")
               = Ok ());
             failwith "bracket body")
       with
      | Exit.Failure
          (Cause.Suppressed
             {
               primary = Cause.Die (Failure body, _);
               finalizer = Cause.Die (Failure release, _);
             }) ->
          check_bool "acquire_use_release suppresses release failure after defect" true
            (body = "bracket body" && release = "bracket release")
      | _ -> Alcotest.fail "acquire_use_release suppresses release failure after defect");
      let released = ref 0 in
      let result =
        Retry.repeat ~clock:env#mono_clock (Schedule.recurs 3) (fun () ->
            match
              Scope.run (fun sw ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw
                       ~acquire:(fun () -> Ok ())
                       ~release:(fun () -> incr released)
                    = Ok ());
                  Ok 1)
            with
            | Exit.Success value -> Ok value
            | _ -> Alcotest.fail "repeat scoped release")
      in
      check_bool "repeat releases resources each iteration" true
        (result = Ok 3 && !released = 4))

let retry_race_stress () =
  Eio_main.run (fun env ->
      for rounds = 1 to 20 do
        let live = ref 0 and attempts = ref 0 in
        let outcome =
          Retry.retry ~clock:env#mono_clock (Schedule.recurs rounds) (fun () ->
              incr attempts;
              match
                Scope.run (fun sw ->
                    check_bool "scripted resource acquisition succeeds" true
                      (Support.acquire_release ~sw
                         ~acquire:(fun () ->
                           incr live;
                           Ok ())
                         ~release:(fun () -> decr live)
                      = Ok ());
                    if !attempts <= rounds then Error !attempts else Ok 1)
              with
              | Exit.Success value -> Ok value
              | Exit.Failure (Cause.Fail error) -> Error error
              | _ -> Alcotest.fail "retry resource accumulation systematic")
        in
        check_bool "retry resource accumulation systematic" true (outcome = Ok 1);
        check_int "nested scope catch retry releases all" 0 !live;
        let result =
          Scope.run (fun sw ->
              Concurrent.race ~sw
                [
                  (fun () ->
                    check_bool "scripted resource acquisition succeeds" true
                      (Support.acquire_release ~sw
                         ~acquire:(fun () ->
                           incr live;
                           Ok ())
                         ~release:(fun () -> decr live)
                      = Ok ());
                    Error "first");
                  (fun () ->
                    Eio.Fiber.yield ();
                    Retry.retry ~clock:env#mono_clock (Schedule.recurs 1)
                      (let seen = ref 0 in
                       fun () ->
                         incr seen;
                         if !seen = 1 then Error "again" else Ok 2));
                ])
        in
        (match result with
        | Exit.Success 2 -> ()
        | _ -> Alcotest.fail "race+retry resources released on scope exit");
        check_int "race+retry resources released on scope exit" 0 !live
      done)

let parallel_resource_edges () =
  Eio_main.run (fun _ ->
      let live = ref 0 and cleaned = ref 0 in
      let result =
        Eio.Cancel.sub (fun ctx ->
            Eio.Switch.run (fun outer ->
                Eio.Fiber.fork ~sw:outer (fun () ->
                    Eio.Fiber.yield ();
                    Eio.Cancel.cancel ctx (Failure "outside"));
                Scope.run (fun sw ->
                    Concurrent.all ~sw
                      (List.init 8 (fun _ () ->
                           check_bool "scripted resource acquisition succeeds" true
                             (Support.acquire_release ~sw
                                ~acquire:(fun () ->
                                  incr live;
                                  Ok ())
                                ~release:(fun () ->
                                  Eio.Fiber.yield ();
                                  decr live;
                                  incr cleaned)
                             = Ok ());
                           Eio.Fiber.await_cancel ())))))
      in
      (match result with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "acquire_all_par parent interruption rollback");
      check_int "acquire_all_par cancellation late completion" 0 !live;
      check_int "acquire_all_par interrupted resources released" 8 !cleaned;
      let result =
        Scope.run (fun sw ->
            Concurrent.all ~sw
              [
                (fun () ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw
                       ~acquire:(fun () -> Ok ())
                       ~release:(fun () -> failwith "parallel release")
                    = Ok ());
                  Eio.Fiber.yield ();
                  Error "parallel body");
                (fun () -> Eio.Fiber.await_cancel ());
              ])
      in
      (match result with
      | Exit.Failure
          (Cause.Suppressed
             {
               primary = Cause.Fail "parallel body";
               finalizer = Cause.Die (Failure _, _);
             }) ->
          ()
      | _ -> Alcotest.fail "acquire_all_par rollback release diagnostics");
      let live = ref 0 in
      let result =
        Scope.run (fun sw ->
            Concurrent.all ~sw
              [
                (fun () ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw
                       ~acquire:(fun () ->
                         incr live;
                         Ok ())
                       ~release:(fun () -> decr live)
                    = Ok ());
                  Eio.Fiber.await_cancel ());
                (fun () ->
                  Eio.Fiber.yield ();
                  failwith "acquire defect");
              ])
      in
      (match result with
      | Exit.Failure (Cause.Die (Failure _, _)) -> ()
      | _ -> Alcotest.fail "acquire_all_par acquire defect rollback");
      check_int "acquire_all_par acquire defect leaves no live handles" 0 !live;
      let result =
        Scope.run (fun sw ->
            Concurrent.all ~sw
              [
                (fun () ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw
                       ~acquire:(fun () -> Ok ())
                       ~release:(fun () -> failwith "release diagnostic")
                    = Ok ());
                  Ok 1);
                (fun () -> Ok 2);
              ])
      in
      match result with
      | Exit.Failure (Cause.Finalizer (Cause.Die (Failure _, _))) -> ()
      | _ -> Alcotest.fail "acquire_all_par release diagnostics")

let supervisor_edges () =
  Eio_main.run (fun _ ->
      let exited = ref 0 in
      let pending () =
        Fun.protect (fun () -> Eio.Fiber.await_cancel ()) ~finally:(fun () -> incr exited)
      in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw
               (fun () ->
                 Stdlib.Result.map
                   (fun _ -> ())
                   (Eio.Switch.run (fun inner ->
                        Concurrent.par ~sw:inner
                          (fun () ->
                            Eio.Fiber.yield ();
                            Error "background")
                          pending)))
               pending)
       with
      | Exit.Failure (Cause.Fail "background") -> ()
      | _ -> Alcotest.fail "with_background nested par background failure remains");
      check_int "nested background and body losers exited" 2 !exited;
      let own_stopped = ref 0 and own_ready = ref 0 in
      let nested_pending () =
        Fun.protect
          (fun () ->
            incr own_ready;
            Eio.Fiber.await_cancel ())
          ~finally:(fun () -> incr own_stopped)
      in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw
               (fun () ->
                 Stdlib.Result.map
                   (fun _ -> ())
                   (Eio.Switch.run (fun inner ->
                        Concurrent.par ~sw:inner nested_pending nested_pending)))
               (fun () ->
                 let rec wait n =
                   if !own_ready = 2 then ()
                   else if n = 0 then Alcotest.fail "nested par did not start"
                   else (
                     Eio.Fiber.yield ();
                     wait (n - 1))
                 in
                 wait 100;
                 Ok 3))
       with
      | Exit.Success 3 -> ()
      | _ -> Alcotest.fail "with_background nested par own-stop preserves body");
      check_int "with_background nested par own-stop awaits both children" 2 !own_stopped;
      let cleanup = ref 0 and ready = ref 0 in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw
               (fun () ->
                 Stdlib.Result.map
                   (fun _ -> ())
                   (Eio.Switch.run (fun inner ->
                        Concurrent.par ~sw:inner
                          (fun () ->
                            Fun.protect
                              (fun () ->
                                incr ready;
                                Eio.Fiber.await_cancel ())
                              ~finally:(fun () ->
                                incr cleanup;
                                failwith "nested-cleanup-die"))
                          (fun () ->
                            incr ready;
                            Fun.protect pending ~finally:(fun () -> incr cleanup)))))
               (fun () ->
                 let rec await_ready retries =
                   if !ready = 2 then ()
                   else if retries = 0 then
                     Alcotest.fail "nested background did not start"
                   else (
                     Eio.Fiber.yield ();
                     await_ready (retries - 1))
                 in
                 await_ready 100;
                 Ok 1))
       with
      | Exit.Failure (Cause.Die (ex, _)) ->
          check_bool "with_background nested par cleanup Die remains" true
            (String.starts_with
               ~prefix:"Fun.Finally_raised: Failure(\"nested-cleanup-die\")"
               (Printexc.to_string ex))
      | Exit.Success _ ->
          Alcotest.failf "nested par cleanup defect lost: success cleanup=%d" !cleanup
      | Exit.Failure cause ->
          Alcotest.failf "nested par cleanup defect lost: %a"
            (Cause.pp_compact Format.pp_print_string)
            cause);
      check_int "nested par cleanup awaited" 2 !cleanup;
      let cancelled_outcome =
        Eio.Cancel.sub (fun ctx ->
            Eio.Switch.run (fun outer ->
                Eio.Fiber.fork ~sw:outer (fun () ->
                    Eio.Fiber.yield ();
                    Eio.Cancel.cancel ctx (Failure "outside"));
                Scope.run (fun sw -> Concurrent.with_background ~sw pending pending)))
      in
      (match cancelled_outcome with
      | Exit.Failure (Cause.Interrupt None) -> ()
      | _ -> Alcotest.fail "with_background nested par external cancel remains");
      check_int "external cancellation awaits nested cleanup" 5 !exited;
      let nested =
        Scope.run (fun sw ->
            match
              Scope.run (fun child ->
                  check_bool "scripted resource acquisition succeeds" true
                    (Support.acquire_release ~sw:child
                       ~acquire:(fun () -> Ok ())
                       ~release:(fun () -> incr exited)
                    = Ok ());
                  Ok 3)
            with
            | Exit.Success n -> Concurrent.with_background ~sw pending (fun () -> Ok n)
            | _ -> Alcotest.fail "nested scopes compose")
      in
      (match nested with
      | Exit.Success 3 -> ()
      | _ -> Alcotest.fail "nested scopes compose result");
      check_int "nested scopes compose finalization" 7 !exited)

let supervisor_publication_cases () =
  Eio_main.run (fun _ ->
      let cleanup_runs = ref 0 in
      let dirty () =
        Fun.protect
          (fun () -> Eio.Fiber.await_cancel ())
          ~finally:(fun () ->
            incr cleanup_runs;
            Eio.Cancel.protect (fun () -> Eio.Fiber.yield ());
            failwith "late-background-cleanup")
      in
      let check_cleanup name outcome =
        match outcome with
        | Exit.Success _ -> Alcotest.fail (name ^ " swallowed cleanup defect")
        | Exit.Failure cause ->
            let rendered =
              Format.asprintf "%a" (Cause.pp_compact Format.pp_print_string) cause
            in
            let needle = "late-background-cleanup" in
            let rec contains i =
              i + String.length needle <= String.length rendered
              && (String.sub rendered i (String.length needle) = needle
                 || contains (i + 1))
            in
            if not (contains 0) then Alcotest.failf "%s: %s" name rendered
      in
      let run body =
        Scope.run (fun sw ->
            Concurrent.with_background ~sw dirty (fun () ->
                Eio.Fiber.yield ();
                body ()))
      in
      check_cleanup "background cleanup after body success matches old shape"
        (run (fun () -> Ok 1));
      check_int "background loser publishes after cancellation before assembly" 1
        !cleanup_runs;
      check_cleanup "background cleanup after body failure matches old shape"
        (run (fun () -> Error "body"));
      check_cleanup "background cleanup after body defect matches old shape"
        (run (fun () -> failwith "body defect"));
      check_int "all late background cleanup defects awaited" 3 !cleanup_runs;
      let cleaned = ref false in
      (match
         Scope.run (fun sw ->
             Concurrent.with_background ~sw
               (fun () ->
                 Fun.protect
                   (fun () -> Eio.Fiber.await_cancel ())
                   ~finally:(fun () -> cleaned := true))
               (fun () ->
                 Eio.Fiber.yield ();
                 Fun.protect (fun () -> Ok 1) ~finally:(fun () -> failwith "body-cleanup")))
       with
      | Exit.Failure (Cause.Die (ex, _)) ->
          check_bool "background winner preserves body cleanup failure" true
            (String.starts_with ~prefix:"Fun.Finally_raised: Failure(\"body-cleanup\")"
               (Printexc.to_string ex))
      | _ -> Alcotest.fail "background winner preserves body cleanup failure");
      check_bool "background winner awaits losing child" true !cleaned;
      let interruption bg =
        Scope.run (fun sw ->
            if bg then
              Concurrent.with_background ~sw
                (fun () -> Eio.Fiber.await_cancel ())
                (fun () -> raise (Eio.Cancel.Cancelled (Failure "interrupted")))
            else
              match
                Concurrent.par ~sw
                  (fun () -> Eio.Fiber.await_cancel ())
                  (fun () -> raise (Eio.Cancel.Cancelled (Failure "interrupted")))
              with
              | Ok _ -> Ok 1
              | Error e -> Error e)
      in
      check_bool "with_background body interruption matches par cause shape" true
        (match (interruption true, interruption false) with
        | Exit.Failure (Cause.Interrupt None), Exit.Failure (Cause.Interrupt None) -> true
        | _ -> false);
      for _ = 1 to 20 do
        let outcome =
          Scope.run (fun sw ->
              let ready, notify = Eio.Promise.create () in
              Concurrent.with_background ~sw
                (fun () ->
                  Eio.Promise.await ready;
                  Error "bg")
                (fun () ->
                  Eio.Promise.resolve notify ();
                  Ok 1))
        in
        check_bool "with_background same-release publication order chooses one winner"
          true
          (outcome = Exit.Success 1 || outcome = Exit.Failure (Cause.Fail "bg"))
      done)

let tests =
  [
    ( "v1 supervisor publication ^nport-ivyn",
      [
        Alcotest.test_case "winner order and late cleanup defects" `Quick
          supervisor_publication_cases;
      ] );
    ( "v1 supervisor edges ^nport-ivyn",
      [
        Alcotest.test_case "nested failures and external cancellation" `Quick
          supervisor_edges;
      ] );
    ( "v1 parallel resource edges ^nport-bo4a",
      [
        Alcotest.test_case "interrupted admission and release diagnostics" `Quick
          parallel_resource_edges;
      ] );
    ( "v1 stress retry and race ^nport-ozuw",
      [
        Alcotest.test_case "bounded retry and race resource accumulation" `Quick
          retry_race_stress;
      ] );
    ( "v1 resource boundary ^nport-bo4a",
      [
        Alcotest.test_case "root finalizers and repeated release" `Quick
          resource_edge_cases;
      ] );
    ( "v1 schedule boundaries ^nport-rry6",
      [ Alcotest.test_case "fixed overrun and bounded elapsed" `Quick cadence_cases ] );
    ( "v1 nested supervision ^nport-ivyn",
      [
        Alcotest.test_case "nested par, race, finalizer settlement" `Quick
          concurrent_cases;
      ] );
    ( "v1 bracket and parallel acquisition ^nport-bo4a",
      [
        Alcotest.test_case "bracket result and cleanup outcomes" `Quick bracket_cases;
        Alcotest.test_case "parallel admission, rollback and order" `Quick
          parallel_resource_cases;
      ] );
    ( "v1 virtual clock ^nport-kaym",
      [ Alcotest.test_case "four sleeper deadlines" `Quick clock_cases ] );
    ( "v1 retry resource ^nport-rry6",
      [
        Alcotest.test_case "resource, failure, repeat timeout" `Quick retry_resource_cases;
      ] );
    ( "v1 stress compositions ^nport-ozuw",
      [
        Alcotest.test_case "bounded all with owned nested resources" `Quick
          stress_compositions;
      ] );
  ]
