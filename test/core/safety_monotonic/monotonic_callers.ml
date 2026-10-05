open Ox

(* Ticket 15 ^safe-p9cw ^safe-8peq ^safe-5a9k: independent virtual wall and
   backend monotonic clocks; never change or sleep on the host wall clock. *)
let runtime_clock env = env#mono_clock
let ns clock = Mtime.to_uint64_ns (Eio.Time.Mono.now clock)
let check_ns = Alcotest.(check int64)
let check_bool = Alcotest.(check bool)

let run ?(origin_ns = 0L) f =
  Eio_mock.Backend.run_full (fun env ->
      Eio_mock.Clock.Mono.set_time env#mono_clock (Mtime.of_uint64_ns origin_ns);
      let result =
        Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds env#mono_clock 0.5) (fun () ->
            let wall = Eio_mock.Clock.make () in
            f
              object
                method clock = wall
                method mono_clock = env#mono_clock
              end
              ())
      in
      check_bool "all monotonic timer registrations removed" false
        (Eio_mock.Clock.Mono.try_advance env#mono_clock);
      result)

let retry_elapsed ?(origin_ns = 0L) wall_after () =
  run ~origin_ns (fun env _ ->
      Eio_mock.Clock.set_time env#clock 1000.;
      let clock = runtime_clock env in
      let steps = ref [] and calls = ref 0 in
      let schedule =
        Schedule.modify_delay
          (fun (elapsed, _) _ ->
            steps := Duration.to_ms elapsed :: !steps;
            Duration.zero)
          (Schedule.both Schedule.elapsed (Schedule.recurs 2))
      in
      let actual =
        Retry.retry ~clock schedule (fun () ->
            incr calls;
            if !calls > 1 then Eio.Time.Mono.sleep env#mono_clock 0.01;
            if !calls = 2 then Eio_mock.Clock.set_time env#clock wall_after;
            Error "retry")
      in
      Alcotest.(check (result unit string))
        "last failure preserved" (Error "retry") actual;
      Alcotest.(check (list int)) "monotonic schedule elapsed" [ 0; 10 ] (List.rev !steps))

let limiter config wall_after () =
  run (fun env _ ->
      Eio_mock.Clock.set_time env#clock 1000.;
      Eio.Switch.run (fun sw ->
          let clock = runtime_clock env in
          let limiter = Rate_limiter.create ~sw ~clock config in
          check_bool "initial permit" true
            (Rate_limiter.run_or_drop limiter (fun () -> ()) = Some ());
          Eio_mock.Clock.set_time env#clock wall_after;
          check_bool "wall jump does not refill" true
            (Rate_limiter.run_or_drop limiter (fun () -> ()) = None);
          Eio.Time.Mono.sleep env#mono_clock 0.099;
          check_bool "not before period" true
            (Rate_limiter.run_or_drop limiter (fun () -> ()) = None);
          Eio.Time.Mono.sleep env#mono_clock 0.001;
          check_bool "refilled at period" true
            (Rate_limiter.run_or_drop limiter (fun () -> ()) = Some ())))

let select_deadline wall_after () =
  run (fun env _ ->
      Eio_mock.Clock.set_time env#clock 1000.;
      Eio.Switch.run (fun sw ->
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.Mono.sleep env#mono_clock 0.001;
              Eio_mock.Clock.set_time env#clock wall_after);
          let start = ns env#mono_clock in
          let actual =
            Select.select
              [
                Select.timeout_clause ~clock:(runtime_clock env) (Duration.ms 100)
                  (fun () -> 42);
              ]
          in
          Alcotest.(check int) "timeout handler" 42 actual;
          check_ns "relative deadline stays monotonic" 100_000_000L
            (Int64.sub (ns env#mono_clock) start)))

let supervisor_window wall_after elapsed_ms expected () =
  run (fun env _ ->
      Eio_mock.Clock.set_time env#clock 1000.;
      Eio.Switch.run (fun sw ->
          match
            Scope.supervised_error ~sw (fun scope ->
                let triggers = Eio.Stream.create 1 in
                let events = Eio.Stream.create 10 in
                let child : string Supervisor.child =
                  Supervisor.child ~id:"child" ~restart:Transient ~shutdown:Brutal_kill
                    (fun ctx ->
                      let trigger, resolve = Eio.Promise.create () in
                      Eio.Stream.add triggers resolve;
                      ctx.ready ();
                      Eio.Promise.await trigger;
                      Error "failure")
                in
                match
                  Supervisor.start ~scope ~clock:(runtime_clock env)
                    ~intensity:{ max_restarts = 1; window = Duration.ms 100 }
                    ~on_event:(function
                      | Supervisor.Restart_attempt _ -> Eio.Stream.add events "restart"
                      | Supervisor.Shutting_down `Restart_intensity_exceeded ->
                          Eio.Stream.add events "exceeded"
                      | _ -> ())
                    ~strategy:One_for_one [ child ]
                with
                | Error _ -> Alcotest.fail "supervisor start"
                | Ok supervisor ->
                    Eio.Promise.resolve (Eio.Stream.take triggers) ();
                    Alcotest.(check string)
                      "first restart" "restart" (Eio.Stream.take events);
                    let next = Eio.Stream.take triggers in
                    Eio.Time.Mono.sleep env#mono_clock (float elapsed_ms /. 1000.);
                    Eio_mock.Clock.set_time env#clock wall_after;
                    Eio.Promise.resolve next ();
                    Alcotest.(check string)
                      "restart budget uses monotonic window" expected
                      (Eio.Stream.take events);
                    (match Supervisor.stop supervisor with
                    | Supervisor.Stopped when expected = "restart" -> ()
                    | Supervisor.Intensity_exceeded _ when expected = "exceeded" -> ()
                    | _ -> Alcotest.fail "supervisor outcome changed");
                    Ok ())
          with
          | Ok () -> ()
          | Error (`Restart_intensity_exceeded _) when expected = "exceeded" -> ()
          | _ -> Alcotest.fail "owning scope failed"))

(* ^safe-p9cw ^safe-5a9k: cancellation cancels/joins waits even after a wall jump. *)
let cancellation prepare () =
  run (fun env _ ->
      Eio.Switch.run (fun sw ->
          let pending, verify = prepare env sw in
          let entered, start = Eio.Promise.create () in
          let cleaned = ref false in
          let before = ns env#mono_clock in
          let outcome =
            Eio.Fiber.first
              (fun () ->
                Fun.protect
                  (fun () ->
                    Eio.Promise.resolve start ();
                    pending ();
                    "completed")
                  ~finally:(fun () -> cleaned := true))
              (fun () ->
                Eio.Promise.await entered;
                Eio.Time.Mono.sleep env#mono_clock 0.001;
                Eio_mock.Clock.set_time env#clock (-1000000.);
                Eio.Time.Mono.sleep env#mono_clock 0.009;
                "cancelled")
          in
          Alcotest.(check string)
            "wait cancelled, not returned as ordinary result" "cancelled" outcome;
          check_bool "waiter cleanup joined" true !cleaned;
          check_ns "cancellation prompt" 10_000_000L
            (Int64.sub (ns env#mono_clock) before);
          verify ()))

let cancel_retry env _ =
  let calls = ref 0 in
  ( (fun () ->
      match
        Retry.retry ~clock:(runtime_clock env)
          (Schedule.spaced (Duration.ms 100))
          (fun () ->
            incr calls;
            Error "retry")
      with
      | Ok _ | Error _ -> Alcotest.fail "retry returned without cancellation"),
    fun () -> Alcotest.(check int) "no additional attempt" 1 !calls )

let cancel_repeat env _ =
  let calls = ref 0 in
  ( (fun () ->
      match
        Retry.repeat ~clock:(runtime_clock env)
          (Schedule.spaced (Duration.ms 100))
          (fun () ->
            incr calls;
            Ok ())
      with
      | Ok _ | Error _ -> Alcotest.fail "repeat returned without cancellation"),
    fun () -> Alcotest.(check int) "no additional iteration" 1 !calls )

let cancel_limiter env sw =
  let limiter =
    Rate_limiter.create ~sw ~clock:(runtime_clock env)
      (Fixed_window { n = 1; per = Duration.ms 100 })
  in
  Rate_limiter.run limiter (fun () -> ());
  let called = ref false in
  ( (fun () -> Rate_limiter.run limiter (fun () -> called := true)),
    fun () -> check_bool "cancelled acquisition did not run callback" false !called )

let cancel_select env _ =
  let called = ref false in
  ( (fun () ->
      Select.select
        [
          Select.timeout_clause ~clock:(runtime_clock env) (Duration.ms 100) (fun () ->
              called := true);
        ]),
    fun () -> check_bool "cancelled selection did not fire timeout" false !called )

let cancel_supervisor env sw =
  let live = ref 0 and cleaned = ref false in
  ( (fun () ->
      match
        Scope.supervised_error ~sw (fun scope ->
            let child =
              Supervisor.child ~id:"cancel" ~restart:Transient ~shutdown:Brutal_kill
                (fun ctx ->
                  incr live;
                  Fun.protect
                    (fun () ->
                      ctx.ready ();
                      Eio.Fiber.await_cancel ())
                    ~finally:(fun () ->
                      decr live;
                      cleaned := true))
            in
            match
              Supervisor.start ~scope ~clock:(runtime_clock env)
                ~intensity:{ max_restarts = 1; window = Duration.ms 100 }
                ~on_event:(fun _ -> ())
                ~strategy:One_for_one [ child ]
            with
            | Error _ -> Alcotest.fail "supervisor startup"
            | Ok _ -> Eio.Fiber.await_cancel ())
      with
      | Ok _ | Error _ -> Alcotest.fail "supervisor returned without cancellation"),
    fun () ->
      Alcotest.(check int) "cancelled supervisor joined child" 0 !live;
      check_bool "child cleanup completed" true !cleaned )

(* ^safe-8peq: reading a monotonic provider can itself consume elapsed time. *)
let advancing_constructor_origin () =
  let module Clock = struct
    type t = Mtime.t ref
    type time = Mtime.t

    let now state =
      let at = !state in
      (state :=
         match Mtime.add_span at (Mtime.Span.of_uint64_ns 1_000_000L) with
         | Some next -> next
         | None -> Alcotest.fail "advancing provider overflow");
      at

    let sleep_until _ _ = Alcotest.fail "granted acquisition must not sleep"
  end in
  run (fun _ _ ->
      Eio.Switch.run (fun sw ->
          let clock =
            Eio.Resource.T (ref (Mtime.of_uint64_ns 0L), Eio.Time.Pi.clock (module Clock))
          in
          let constructed = ref None and acquired = ref None in
          let limiter =
            Rate_limiter.create ~sw ~clock
              (Custom
                 (fun ~now_ms ->
                   constructed := Some now_ms;
                   {
                     try_acquire =
                       (fun ~now_ms ->
                         acquired := Some now_ms;
                         Granted);
                   }))
          in
          Alcotest.(check (option int))
            "constructor receives exact local origin" (Some 0) !constructed;
          Rate_limiter.run limiter (fun () -> ());
          Alcotest.(check (option int))
            "acquisition still samples elapsed monotonic time" (Some 1) !acquired))

let native_milliseconds () =
  run ~origin_ns:9_000_000_000_000_123_456L (fun env _ ->
      Eio.Switch.run (fun sw ->
          let seen = ref [] in
          let limiter =
            Rate_limiter.create ~sw ~clock:(runtime_clock env)
              (Custom
                 (fun ~now_ms ->
                   seen := [ now_ms ];
                   {
                     try_acquire =
                       (fun ~now_ms ->
                         seen := now_ms :: !seen;
                         Granted);
                   }))
          in
          Eio.Time.Mono.sleep_span env#mono_clock (Mtime.Span.of_uint64_ns 999_999L);
          Rate_limiter.run limiter (fun () -> ());
          Eio_mock.Clock.set_time env#clock 1_000_000.;
          Eio.Time.Mono.sleep_span env#mono_clock (Mtime.Span.of_uint64_ns 1L);
          Rate_limiter.run limiter (fun () -> ());
          Alcotest.(check (list int))
            "native subtraction before millisecond truncation" [ 0; 0; 1 ]
            (List.rev !seen)))

let select_handler () =
  run (fun env _ ->
      Eio.Switch.run (fun sw ->
          let channel : (int, string) Channel.t = Channel.create () in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.Mono.sleep env#mono_clock 0.001;
              match Channel.send channel 7 with
              | Ok () -> ()
              | Error _ -> Alcotest.fail "sender unexpectedly closed");
          let value =
            Select.select
              [
                Select.receive_clause channel (function
                  | Ok value ->
                      Eio.Time.Mono.sleep env#mono_clock 0.2;
                      value
                  | Error _ -> Alcotest.fail "channel unexpectedly closed");
                Select.timeout_clause ~clock:(runtime_clock env) (Duration.ms 100)
                  (fun () -> Alcotest.fail "losing timeout fired");
              ]
          in
          Alcotest.(check int)
            "committed handler is not cancelled by losing timer" 7 value))

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "ticket15 monotonic callers"
    [
      ( "safe-p9cw safe-8peq safe-5a9k",
        [
          case "retry forward" (retry_elapsed 1000000.);
          case "retry backward" (retry_elapsed (-1000.));
          case "retry at large monotonic origin"
            (retry_elapsed ~origin_ns:9_000_000_000_000_123_456L 1000000.);
          case "fixed window forward"
            (limiter (Fixed_window { n = 1; per = Duration.ms 100 }) 1000000.);
          case "sliding window forward"
            (limiter (Sliding_window { n = 1; per = Duration.ms 100 }) 1000000.);
          case "token bucket backward"
            (limiter (Token_bucket { capacity = 1; per = Duration.ms 100 }) (-1000.));
          case "select forward" (select_deadline 1000000.);
          case "select backward" (select_deadline (-1000.));
          case "supervisor forward inside window"
            (supervisor_window 1000000. 10 "exceeded");
          case "supervisor backward at boundary"
            (supervisor_window (-1000.) 100 "restart");
          case "retry cancellation under jump" (cancellation cancel_retry);
          case "repeat cancellation under jump" (cancellation cancel_repeat);
          case "limiter cancellation under jump" (cancellation cancel_limiter);
          case "select cancellation under jump" (cancellation cancel_select);
          case "supervisor cancellation under jump" (cancellation cancel_supervisor);
          case "large native origin sub-ms precision" native_milliseconds;
          case "selected handler outlives losing deadline" select_handler;
          case "advancing provider constructor origin" advancing_constructor_origin;
        ] );
    ]
