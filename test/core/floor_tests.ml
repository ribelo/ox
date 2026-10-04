(* Row 46: rate limiter, channels and select, resources, Duration at Ox's surface, the
   design documents. Every case cites its story IDs (nfloor IDs). Time is Eio_mock's
   virtual clock, which advances by itself when every fiber sleeps. *)
open Ox

let check_bool = Alcotest.(check bool)
let check_int = Alcotest.(check int)
let check_float = Alcotest.(check (float 0.0001))
let check_floats = Alcotest.(check (list (float 0.0001)))

let with_mock f =
  Eio_mock.Backend.run_full (fun env -> Eio.Switch.run (fun sw -> f env#clock sw))

let now = Eio.Time.now

(* Start times of [n] consecutive [Rate_limiter.run]s. *)
let starts clock limiter n =
  List.init n (fun _ -> Rate_limiter.run limiter (fun () -> now clock))

(* ---- nfloor-p4ae: the three algorithms ----------------------------------------------- *)

let fixed_window () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock (Fixed_window { n = 2; per = Duration.seconds 1 })
      in
      check_floats "two per window, the rest wait for the next window"
        [ 0.; 0.; 1.; 1.; 2. ] (starts clock limiter 5);
      (* windows are aligned to creation: a burst may straddle a boundary *)
      let limiter =
        Rate_limiter.create ~sw ~clock (Fixed_window { n = 2; per = Duration.seconds 1 })
      in
      let base = now clock in
      Eio.Time.sleep clock 0.9;
      check_floats "boundary burst"
        [ base +. 0.9; base +. 0.9; base +. 1.; base +. 1. ]
        (starts clock limiter 4))

let sliding_window () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock
          (Sliding_window { n = 2; per = Duration.seconds 1 })
      in
      Eio.Time.sleep clock 0.9;
      check_floats "never more than n in any interval of length per"
        [ 0.9; 0.9; 1.9; 1.9 ] (starts clock limiter 4);
      let limiter =
        Rate_limiter.create ~sw ~clock
          (Sliding_window { n = 2; per = Duration.seconds 1 })
      in
      let base = now clock in
      let first = Rate_limiter.run limiter (fun () -> now clock) in
      Eio.Time.sleep clock 0.4;
      let rest = starts clock limiter 2 in
      check_floats "each permit returns per after its own start"
        [ base; base +. 0.4; base +. 1.0 ]
        (first :: rest))

let token_bucket () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock
          (Token_bucket { capacity = 3; per = Duration.ms 100 })
      in
      check_floats "a full bucket bursts, then one per refill" [ 0.; 0.; 0.; 0.1; 0.2 ]
        (starts clock limiter 5);
      Eio.Time.sleep clock 5.0;
      let base = now clock in
      check_floats "idle time refills to capacity and no further"
        [ base; base; base; base +. 0.1 ]
        (starts clock limiter 4))

let run_or_drop () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock (Fixed_window { n = 1; per = Duration.seconds 1 })
      in
      let ran = ref 0 in
      let attempt () =
        Rate_limiter.run_or_drop limiter (fun () ->
            incr ran;
            !ran)
      in
      check_bool "first is admitted" true (attempt () = Some 1);
      check_bool "second is dropped" true (attempt () = None);
      check_int "a dropped operation is not run" 1 !ran;
      check_float "dropping did not wait" 0. (now clock);
      Eio.Time.sleep clock 1.0;
      check_bool "next window admits again" true (attempt () = Some 2))

let run_passes_results_through () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock
          (Token_bucket { capacity = 5; per = Duration.ms 10 })
      in
      check_bool "an Error is returned unchanged" true
        (Rate_limiter.run limiter (fun () -> (Error `Nope : (int, [> `Nope ]) result))
        = Error `Nope);
      check_bool "an exception propagates unchanged" true
        (match Rate_limiter.run limiter (fun () -> failwith "boom") with
        | exception Failure _ -> true
        | _ -> false))

let waiting_is_cancellable () =
  with_mock (fun clock sw ->
      let limiter =
        Rate_limiter.create ~sw ~clock (Fixed_window { n = 1; per = Duration.seconds 10 })
      in
      ignore (Rate_limiter.run limiter (fun () -> ()));
      let outcome =
        Eio.Fiber.first
          (fun () ->
            Rate_limiter.run limiter (fun () -> ());
            `Ran)
          (fun () ->
            Eio.Time.sleep clock 1.0;
            `Cancelled)
      in
      check_bool "the waiter was cancelled while waiting" true (outcome = `Cancelled);
      check_float "the cancel came at 1s" 1.0 (now clock);
      Eio.Time.sleep clock 9.0;
      check_bool "the cancelled wait consumed no permit" true
        (Rate_limiter.run_or_drop limiter (fun () -> ()) = Some ());
      check_bool "and the window holds n" true
        (Rate_limiter.run_or_drop limiter (fun () -> ()) = None))

let validation () =
  with_mock (fun clock sw ->
      let bad config =
        match Rate_limiter.create ~sw ~clock config with
        | exception Invalid_argument _ -> true
        | _ -> false
      in
      check_bool "n < 1" true (bad (Fixed_window { n = 0; per = Duration.seconds 1 }));
      check_bool "capacity < 1" true
        (bad (Token_bucket { capacity = 0; per = Duration.seconds 1 }));
      check_bool "zero period" true (bad (Sliding_window { n = 1; per = Duration.zero }));
      let finished = ref None in
      Eio.Switch.run (fun inner -> finished := Some inner);
      check_bool "sw is checked" true
        (match
           Rate_limiter.create ~sw:(Option.get !finished) ~clock
             (Fixed_window { n = 1; per = Duration.seconds 1 })
         with
        | exception Invalid_argument _ -> true
        | _ -> false))

(* ---- nfloor-ygtz: a custom algorithm ------------------------------------------------- *)

let custom_algorithm () =
  with_mock (fun clock sw ->
      let created_at = ref (-1) and calls = ref 0 in
      (* grants only on whole seconds since creation *)
      let make ~now_ms =
        created_at := now_ms;
        {
          Rate_limiter.try_acquire =
            (fun ~now_ms ->
              incr calls;
              let into = (now_ms - !created_at) mod 1000 in
              if into = 0 then Rate_limiter.Granted
              else Rate_limiter.Wait (Duration.ms (1000 - into)));
        }
      in
      Eio.Time.sleep clock 3.0;
      let limiter = Rate_limiter.create ~sw ~clock (Custom make) in
      check_int "built once, with the clock's time at creation" 3000 !created_at;
      let base = now clock in
      Eio.Time.sleep clock 0.3;
      let granted = Rate_limiter.run limiter (fun () -> now clock) in
      check_float "the algorithm's own waiting decides" (base +. 1.0) granted;
      check_bool "asked again after the wait, not polled" true (!calls = 2))

(* ---- Channel and Select: nfloor-6qf5 nfloor-lchb ------------------------------------- *)

let yield () =
  for _ = 1 to 8 do
    Eio.Fiber.yield ()
  done

let channel_basics () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let c : (int, string) Channel.t = Channel.create ~capacity:2 () in
          check_bool "send" true (Channel.send c 1 = Ok ());
          check_bool "try_send" true (Channel.try_send c 2 = Ok ());
          check_bool "full" true (Channel.try_send c 3 = Error `Full);
          (* a blocked send resumes when room appears, in order *)
          let sent = ref false in
          Eio.Fiber.fork ~sw (fun () ->
              ignore (Channel.send c 3);
              sent := true);
          yield ();
          check_bool "sender blocked on capacity" false !sent;
          check_bool "fifo 1" true (Channel.receive c = Ok 1);
          yield ();
          check_bool "sender resumed" true !sent;
          check_bool "fifo 2" true (Channel.receive c = Ok 2);
          check_bool "fifo 3" true (Channel.try_receive c = Ok 3);
          check_bool "empty" true (Channel.try_receive c = Error `Empty);
          check_bool "capacity 0 refused" true
            (match Channel.create ~capacity:0 () with
            | exception Invalid_argument _ -> true
            | (_ : (int, string) Channel.t) -> false)))

let channel_closing () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          (* done_: the buffer drains, then Done forever; senders are refused *)
          let c : (int, string) Channel.t = Channel.create () in
          ignore (Channel.send c 1);
          Channel.done_ c;
          check_bool "send after done" true (Channel.send c 2 = Error `Done);
          check_bool "drain" true (Channel.receive c = Ok 1);
          check_bool "then done" true (Channel.receive c = Error `Done);
          check_bool "done is sticky" true (Channel.try_receive c = Error `Done);
          (* error: the buffer is dropped, both sides see the error, first error wins *)
          let c : (int, string) Channel.t = Channel.create () in
          ignore (Channel.send c 1);
          Channel.error c "bad";
          Channel.error c "worse";
          Channel.done_ c;
          check_bool "receive sees error" true (Channel.receive c = Error (`Error "bad"));
          check_bool "send sees error" true (Channel.send c 2 = Error (`Error "bad"));
          (* blocked fibers are woken by closing *)
          let c : (int, string) Channel.t = Channel.create ~capacity:1 () in
          let got = ref None in
          Eio.Fiber.fork ~sw (fun () -> got := Some (Channel.receive c));
          yield ();
          Channel.done_ c;
          yield ();
          check_bool "blocked receiver woken by done_" true (!got = Some (Error `Done));
          let c : (int, string) Channel.t = Channel.create ~capacity:1 () in
          ignore (Channel.send c 1);
          let got = ref None in
          Eio.Fiber.fork ~sw (fun () -> got := Some (Channel.send c 2));
          yield ();
          Channel.error c "stop";
          yield ();
          check_bool "blocked sender woken by error" true
            (!got = Some (Error (`Error "stop")))))

type fired = A of int | B of int | Sent_c | Closed_a | Closed_b | Idle | Timed_out

let recv_a c = Select.receive_clause c (function Ok v -> A v | Error _ -> Closed_a)
let recv_b c = Select.receive_clause c (function Ok v -> B v | Error _ -> Closed_b)

let select_receive () =
  Eio_main.run (fun _ ->
      Eio.Switch.run (fun sw ->
          let a : (int, string) Channel.t = Channel.create ()
          and b : (int, string) Channel.t = Channel.create () in
          ignore (Channel.send b 7);
          check_bool "the ready channel fires, the other is untouched" true
            (Select.select [ recv_a a; recv_b b ] = B 7);
          check_bool "a is untouched" true (Channel.try_receive a = Error `Empty);
          (* a blocking select wakes for whichever channel gets a value *)
          let got = ref None in
          Eio.Fiber.fork ~sw (fun () ->
              got := Some (Select.select [ recv_a a; recv_b b ]));
          yield ();
          check_bool "still waiting" true (!got = None);
          ignore (Channel.send a 5);
          yield ();
          check_bool "woken by a" true (!got = Some (A 5));
          (* Select.receive over same-typed channels *)
          ignore (Channel.send b 9);
          check_bool "Select.receive" true (Select.receive [ a; b ] = Ok 9)))

let select_fairness () =
  Eio_main.run (fun _ ->
      let a : (int, string) Channel.t = Channel.create ~capacity:16 ()
      and b : (int, string) Channel.t = Channel.create ~capacity:16 () in
      for i = 1 to 8 do
        ignore (Channel.send a i);
        ignore (Channel.send b i)
      done;
      let fired = List.init 8 (fun _ -> Select.select [ recv_a a; recv_b b ]) in
      let count f = List.length (List.filter f fired) in
      check_int "two always-ready channels are served alternately: a" 4
        (count (function A _ -> true | _ -> false));
      check_int "and b" 4 (count (function B _ -> true | _ -> false)))

let select_send () =
  Eio_main.run (fun _ ->
      let c : (int, string) Channel.t = Channel.create ~capacity:1 ()
      and d : (int, string) Channel.t = Channel.create ~capacity:1 () in
      let send_c =
        Select.send_clause c 10 (function Ok () -> Sent_c | Error _ -> Closed_a)
      in
      check_bool "room in c: the send clause fires" true
        (Select.select [ send_c; recv_b d ] = Sent_c);
      check_bool "the value was sent" true (Channel.try_receive c = Ok 10);
      ignore (Channel.send c 0);
      ignore (Channel.send d 4);
      check_bool "c full, d ready: the receive clause fires" true
        (Select.select [ send_c; recv_b d ] = B 4);
      check_bool "the unfired send did not happen" true (Channel.try_receive c = Ok 0))

let select_default () =
  Eio_main.run (fun _ ->
      let a : (int, string) Channel.t = Channel.create () in
      let default = Select.default_clause (fun () -> Idle) in
      check_bool "nothing ready: default, without blocking" true
        (Select.select [ recv_a a; default ] = Idle);
      ignore (Channel.send a 1);
      check_bool "a ready clause beats the default" true
        (Select.select [ recv_a a; default ] = A 1))

let select_timeout () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      Eio.Switch.run (fun sw ->
          let a : (int, string) Channel.t = Channel.create () in
          let timeout ms =
            Select.timeout_clause ~clock (Duration.ms ms) (fun () -> Timed_out)
          in
          check_bool "no value in time: the timeout clause fires" true
            (Select.select [ recv_a a; timeout 100 ] = Timed_out);
          check_float "after exactly the timeout" 0.1 (now clock);
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Time.sleep clock 0.05;
              ignore (Channel.send a 3));
          let start = now clock in
          check_bool "a value before the deadline wins" true
            (Select.select [ recv_a a; timeout 100 ] = A 3);
          check_float "at the value's time, not the deadline" (start +. 0.05) (now clock);
          ignore (Channel.send a 4);
          check_bool "a ready clause beats a zero timeout" true
            (Select.select [ recv_a a; timeout 0 ] = A 4)))

let select_closed () =
  Eio_main.run (fun _ ->
      let a : (int, string) Channel.t = Channel.create ()
      and b : (int, string) Channel.t = Channel.create () in
      (* handlers see the typed closure; nothing raises *)
      let recv_a' =
        Select.receive_clause a (function
          | Ok v -> `Value v
          | Error `Done -> `A_done
          | Error (`Error e) -> `A_failed e)
      in
      Channel.done_ a;
      check_bool "closed a is an outcome" true (Select.select [ recv_a' ] = `A_done);
      check_bool "Select.receive: Done" true (Select.receive [ a ] = Error `Done);
      let c : (int, string) Channel.t = Channel.create () in
      Channel.error c "bad";
      check_bool "Select.receive: Error carries the payload" true
        (Select.receive [ c ] = Error (`Error "bad"));
      (* a closed channel is ready, so the caller learns of it and drops the clause *)
      ignore (Channel.send b 1);
      let outcomes = List.init 2 (fun _ -> Select.select [ recv_a a; recv_b b ]) in
      check_bool "both fire, closure included" true
        (List.sort compare outcomes = List.sort compare [ Closed_a; B 1 ]);
      let send_closed =
        Select.send_clause a 1 (function
          | Ok () -> Sent_c
          | Error `Done -> Closed_a
          | Error _ -> Idle)
      in
      check_bool "send clause on a closed channel" true
        (Select.select [ send_closed ] = Closed_a))

let select_cancellation_and_misuse () =
  Eio_mock.Backend.run_full (fun env ->
      let clock = env#clock in
      let a : (int, string) Channel.t = Channel.create () in
      let outcome =
        Eio.Fiber.first
          (fun () ->
            ignore (Select.select [ recv_a a ]);
            `Fired)
          (fun () ->
            Eio.Time.sleep clock 1.0;
            `Cancelled)
      in
      check_bool "cancelling a blocked select" true (outcome = `Cancelled);
      ignore (Channel.send a 1);
      check_bool "no clause fired: the element is still there" true
        (Channel.try_receive a = Ok 1);
      let invalid f =
        match f () with exception Invalid_argument _ -> true | _ -> false
      in
      check_bool "empty list" true
        (invalid (fun () -> Select.select ([] : fired Select.clause list)));
      check_bool "two defaults" true
        (invalid (fun () ->
             Select.select
               [
                 Select.default_clause (fun () -> Idle);
                 Select.default_clause (fun () -> Idle);
               ]));
      let t () = Select.timeout_clause ~clock (Duration.ms 1) (fun () -> Timed_out) in
      check_bool "two timeouts" true (invalid (fun () -> Select.select [ t (); t () ]));
      check_bool "receive []" true
        (invalid (fun () -> Select.receive ([] : (int, string) Channel.t list))))

(* ---- nfloor-elwp: resources ----------------------------------------------------------- *)

let resources () =
  Eio_main.run (fun _ ->
      let log = ref [] in
      let note x = log := x :: !log in
      (* value returned, release on the switch, reverse order *)
      Eio.Switch.run (fun sw ->
          let one =
            Resource.use_in_scope ~sw
              (fun () ->
                note "acquire 1";
                1)
              (fun _ -> note "release 1")
          in
          let two =
            Resource.use_in_scope ~sw
              (fun () ->
                note "acquire 2";
                2)
              (fun _ -> note "release 2")
          in
          check_int "values returned" 3 (one + two);
          note "body done");
      Alcotest.(check (list string))
        "reverse order, after the body"
        [ "acquire 1"; "acquire 2"; "body done"; "release 2"; "release 1" ]
        (List.rev !log);
      (* release on failure: exception and typed error *)
      log := [];
      (match
         Eio.Switch.run (fun sw ->
             ignore (Resource.use_in_scope ~sw (fun () -> ()) (fun () -> note "released"));
             failwith "body failed")
       with
      | exception Failure _ -> ()
      | () -> Alcotest.fail "exception swallowed");
      Alcotest.(check (list string)) "released after an exception" [ "released" ] !log;
      log := [];
      let exit =
        Scope.run (fun sw ->
            ignore (Resource.use_in_scope ~sw (fun () -> ()) (fun () -> note "released"));
            (Error "typed" : (unit, string) result))
      in
      check_bool "typed failure is the exit" true
        (exit = Exit.Failure (Cause.Fail "typed"));
      Alcotest.(check (list string)) "released after a typed failure" [ "released" ] !log;
      (* an acquire that raises registers nothing *)
      log := [];
      (match
         Eio.Switch.run (fun sw ->
             Resource.use_in_scope ~sw
               (fun () -> failwith "acquire failed")
               (fun () -> note "released"))
       with
      | exception Failure _ -> ()
      | () -> Alcotest.fail "acquire failure swallowed");
      Alcotest.(check (list string)) "nothing to release" [] !log;
      (* a release failure is a finalizer failure at Scope.run *)
      match
        Scope.run (fun sw ->
            ignore
              (Resource.use_in_scope ~sw
                 (fun () -> ())
                 (fun () -> failwith "release failed"));
            (Ok () : (unit, string) result))
      with
      | Exit.Failure (Cause.Finalizer _ | Cause.Die _ | Cause.Suppressed _) -> ()
      | _ -> Alcotest.fail "release failure lost")

let closeable () =
  Eio_main.run (fun _ ->
      let closed = ref 0 in
      let make () : Eio.Resource.close_ty Eio.Resource.t =
        Eio.Resource.T
          ((), Eio.Resource.handler [ H (Eio.Resource.Close, fun () -> incr closed) ])
      in
      Eio.Switch.run (fun sw ->
          let r = Resource.use_closeable_in_scope ~sw make in
          check_int "open inside the scope" 0 !closed;
          ignore r);
      check_int "Eio.Resource.close ran when the switch ended" 1 !closed)

(* ---- nfloor-twpq: one time type ------------------------------------------------------- *)

let durations () =
  check_float "to_seconds" 0.25 (Duration.to_seconds (Duration.ms 250));
  check_bool "of_seconds" true
    (Duration.equal (Duration.of_seconds 1.5) (Duration.ms 1500));
  check_bool "rounds to the millisecond" true
    (Duration.equal (Duration.of_seconds 0.0004) Duration.zero
    && Duration.equal (Duration.of_seconds 0.0016) (Duration.ms 2));
  check_bool "negative clamps like ms" true
    (Duration.equal (Duration.of_seconds (-3.)) Duration.zero);
  check_bool "roundtrip" true
    (Duration.equal
       (Duration.of_seconds (Duration.to_seconds (Duration.ms 1234)))
       (Duration.ms 1234));
  let raises f = match f () with exception Invalid_argument _ -> true | _ -> false in
  check_bool "nan" true (raises (fun () -> Duration.of_seconds Float.nan));
  check_bool "infinity" true (raises (fun () -> Duration.of_seconds Float.infinity));
  Eio_mock.Backend.run_full (fun env ->
      (* every function of Ox that sleeps or times out takes a Duration *)
      let clock = env#clock in
      Eio.Switch.run (fun sw ->
          ignore
            (Rate_limiter.create ~sw ~clock (Fixed_window { n = 1; per = Duration.ms 5 })));
      check_bool "timeout" true
        (Timeout.timeout ~clock (Duration.ms 5) (fun () ->
             Eio.Time.sleep clock 1.;
             (Ok () : (unit, [> `Timeout ]) result))
        = Error `Timeout);
      check_bool "retry sleeps a Duration" true
        (Retry.retry ~clock (Schedule.recurs 1) (fun () ->
             (Error () : (unit, unit) result))
        = Error ()));
  (* no public interface of the tree takes a bare float for a delay, deadline, interval or timeout *)
  let root = if Sys.file_exists "lib/ox/dune" then "lib" else "../../lib" in
  let read path =
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  let contains hay needle =
    let n = String.length needle in
    let rec go i =
      i + n <= String.length hay && (String.sub hay i n = needle || go (i + 1))
    in
    go 0
  in
  let offenders = ref [] in
  Array.iter
    (fun package ->
      let dir = Filename.concat root package in
      if Sys.is_directory dir then
        Array.iter
          (fun file ->
            if Filename.check_suffix file ".mli" then
              List.iter
                (fun line ->
                  if
                    List.exists (contains line)
                      [
                        "timeout:float";
                        "timeout : float";
                        "deadline:float";
                        "delay:float";
                        "interval:float";
                        "sleep:float";
                      ]
                  then
                    offenders :=
                      (package ^ "/" ^ file ^ ": " ^ String.trim line) :: !offenders)
                (String.split_on_char '\n' (read (Filename.concat dir file))))
          (Sys.readdir dir))
    (Sys.readdir root);
  Alcotest.(check (list string))
    "no float seconds in a public timing parameter" [] !offenders

(* ---- design documents and vocabulary: nfloor-pjnk nfloor-idvp nfloor-t8w5 nfloor-tv7b
   nfloor-37ic nfloor-igt7 nfloor-8qx2 ---------------------------------------------------- *)

let docs () =
  let docs = if Sys.file_exists "docs/why-ox.md" then "docs" else "../../docs" in
  let read name =
    let ic = open_in (Filename.concat docs name) in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  in
  let contains hay needle =
    let n = String.length needle in
    let rec go i =
      i + n <= String.length hay && (String.sub hay i n = needle || go (i + 1))
    in
    go 0
  in
  let expect file phrases =
    let text = read file in
    List.iter (fun p -> check_bool (file ^ ": " ^ p) true (contains text p)) phrases
  in
  expect "design/flow.md"
    [
      "run_foreach";
      "run_to_list";
      "run_drain";
      "run_fold";
      "map_par";
      "grouped_within";
      "lines_utf8";
      "backpressure";
      "Eio.Flow";
      "does nothing until it is run";
      "('a, 'e) t";
      "Leash";
      "Pie";
      "JSONL";
    ];
  expect "design/ox-floor.md"
    [
      "Rate limiter API";
      "OxApp";
      "Actors";
      "Circuit Breaker";
      "have (";
      "spec (";
      "design (flow.md)";
      "rejected (";
    ];
  expect "why-ox.md" [ "Ox is the floor"; "Rate_limiter"; "Select" ];
  expect "../GLOSSARY.md" [ "**Flow**"; "**Rate limiter**"; "**Select**"; "Ox" ];
  let context = read "../GLOSSARY.md" in
  check_bool "retired list unchanged" true
    (contains context
       "effect (as a noun for Ox's type), blueprint, interpreter, runtime, SPI, \
        capability, component, coeffect, capsule, settlement fence, dormant provider, \
        desired state, activation")

let tests =
  [
    ( "Ox floor nfloor-p4ae nfloor-ygtz",
      [
        Alcotest.test_case "nfloor-p4ae fixed window" `Quick fixed_window;
        Alcotest.test_case "nfloor-p4ae sliding window" `Quick sliding_window;
        Alcotest.test_case "nfloor-p4ae token bucket" `Quick token_bucket;
        Alcotest.test_case "nfloor-p4ae run_or_drop" `Quick run_or_drop;
        Alcotest.test_case "nfloor-p4ae results pass through run" `Quick
          run_passes_results_through;
        Alcotest.test_case "nfloor-p4ae waiting is cancellable and free" `Quick
          waiting_is_cancellable;
        Alcotest.test_case "nfloor-p4ae validation and checked switch" `Quick validation;
        Alcotest.test_case "nfloor-ygtz custom algorithm" `Quick custom_algorithm;
        Alcotest.test_case "nfloor-6qf5 channel" `Quick channel_basics;
        Alcotest.test_case "nfloor-lchb channel closing" `Quick channel_closing;
        Alcotest.test_case "nfloor-6qf5 select receive" `Quick select_receive;
        Alcotest.test_case "nfloor-6qf5 select fairness" `Quick select_fairness;
        Alcotest.test_case "nfloor-6qf5 select send and mixed" `Quick select_send;
        Alcotest.test_case "nfloor-6qf5 select default" `Quick select_default;
        Alcotest.test_case "nfloor-6qf5 select timeout" `Quick select_timeout;
        Alcotest.test_case "nfloor-lchb select closed is an outcome" `Quick select_closed;
        Alcotest.test_case "nfloor-6qf5 select cancellation and misuse" `Quick
          select_cancellation_and_misuse;
        Alcotest.test_case "nfloor-elwp use_in_scope" `Quick resources;
        Alcotest.test_case "nfloor-elwp use_closeable_in_scope" `Quick closeable;
        Alcotest.test_case "nfloor-twpq Duration at the surface" `Quick durations;
        Alcotest.test_case
          "nfloor-pjnk nfloor-idvp nfloor-t8w5 nfloor-tv7b nfloor-37ic nfloor-igt7 \
           nfloor-8qx2 documents"
          `Quick docs;
      ] );
  ]
