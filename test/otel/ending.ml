module O = Ox_otel
module L = Ox_observability.Logger

let ok = function
  | Ok value -> value
  | Error error -> Alcotest.failf "exporter: %a" O.pp_error error

(* The first response is latched; later connections can complete independently, so
   owner-release recovery can prove at-least-once resending of an uncertain POST. *)
let with_collector
    ?(response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
    ?(before_reply = fun _ -> ()) ?(mock_http_clock = false) f =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:8 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let port =
            match Eio.Net.listening_addr listener with
            | `Tcp (_, port) -> port
            | _ -> assert false
          in
          let arrivals = Eio.Stream.create 128 in
          let released, release = Eio.Promise.create () in
          let count = ref 0 in
          Eio.Fiber.fork_daemon ~sw (fun () ->
              while true do
                let flow, _ = Eio.Net.accept ~sw listener in
                Eio.Fiber.fork_daemon ~sw (fun () ->
                    let input = Eio.Buf_read.of_flow ~max_size:262144 flow in
                    let target = Eio.Buf_read.line input in
                    let rec headers length =
                      let line = Eio.Buf_read.line input in
                      if line = "" then length
                      else
                        let lower = String.lowercase_ascii line in
                        let length =
                          if String.starts_with ~prefix:"content-length:" lower then
                            int_of_string
                              (String.trim (String.sub line 15 (String.length line - 15)))
                          else length
                        in
                        headers length
                    in
                    let body = Eio.Buf_read.take (headers 0) input in
                    incr count;
                    let index = !count in
                    Eio.Stream.add arrivals (target, body);
                    if index = 1 then Eio.Promise.await released;
                    before_reply index;
                    Eio.Flow.copy_string response flow;
                    Eio.Resource.close flow;
                    `Stop_daemon)
              done;
              `Stop_daemon);
          let clock = Eio_mock.Clock.make () in
          let client =
            if mock_http_clock then Ox_http.Client.create ~sw ~net:env#net ~clock ()
            else Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock ()
          in
          let endpoint = Printf.sprintf "http://127.0.0.1:%d" port in
          Eio.Switch.run (fun owned ->
              Fun.protect
                ~finally:(fun () -> ignore (Eio.Promise.try_resolve release () : bool))
                (fun () -> f env owned client endpoint clock arrivals release))))

let make ?(batch_size = 1) ?(max_queue = 1) ?request_deadline ?on_error ?on_signal_error
    ~caps ~sw ~client ~endpoint ~clock ~budget () =
  O.create ~ending_budget:budget ~caps ~sw ~clock ~http_client:client ~endpoint
    ~service_name:"ending" ~batch_size ~max_queue ?request_deadline ?on_error
    ?on_signal_error ()
  |> ok

let logger env exporter =
  L.create ~service:"ending" ~span_ids:(O.span_ids exporter) ~clock:env#clock
    ~mono_clock:env#mono_clock ~reporter:(O.reporter exporter) ()

let guard env label promise =
  match
    Eio.Time.with_timeout env#clock 0.5 (fun () -> Ok (Eio.Promise.await promise))
  with
  | Ok value -> value
  | Error `Timeout -> Alcotest.fail (label ^ ": deadlock guard fired")

let fork_result ~sw f =
  let result, resolve = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () -> Eio.Promise.resolve resolve (f ()));
  result

let budget = Ox.Duration.ms 30

let advance clock =
  Eio_mock.Clock.set_time clock 1.;
  Eio.Fiber.yield ()

let full_queue_budget ~caps () =
  (* ^notel-056b ^notel-jx0z: the total deadline includes a full-queue Stop admission. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let exporter = make ~caps ~sw ~client ~endpoint ~clock ~budget () in
      let log = logger env exporter in
      L.info log "in flight";
      ignore (Eio.Stream.take arrivals : string * string);
      L.info log "queued";
      let result = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Fiber.yield ();
      Eio.Fiber.yield ();
      advance clock;
      match guard env "full-queue shutdown" result with
      | Error `Drain_deadline -> ()
      | result ->
          ignore (ok result : unit);
          Alcotest.fail "expected total deadline")

let cancelled_shutdown ~caps () =
  (* ^notel-48tm ^notel-s12c: cancelling the admitting waiter must not lose Stop. *)
  with_collector (fun env sw client endpoint clock arrivals release ->
      let exporter = make ~caps ~sw ~client ~endpoint ~clock ~budget () in
      let log = logger env exporter in
      L.info log "in flight";
      ignore (Eio.Stream.take arrivals : string * string);
      L.info log "queued";
      let entered, enter = Eio.Promise.create () in
      let cancelled, cancel_seen = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Cancel.sub (fun cc ->
              Eio.Promise.resolve enter cc;
              match O.shutdown exporter with
              | exception Eio.Cancel.Cancelled _ -> Eio.Promise.resolve cancel_seen ()
              | _ -> Alcotest.fail "caller cancellation was swallowed"));
      let cc = Eio.Promise.await entered in
      Eio.Fiber.yield ();
      Eio.Cancel.cancel cc Exit;
      Eio.Promise.await cancelled;
      let result = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Promise.resolve release ();
      ok (guard env "surviving shutdown waiter" result))

let consumed_flush ~caps () =
  (* ^notel-hjd5 ^notel-d52a ^notel-opp7: a consumed control survives cancellation
     during its metric POST, and the uncertain window is sent at least once again. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let opened, open_ = Eio.Promise.create () in
      let hold, _ = Eio.Promise.create () in
      let owner_done =
        fork_result ~sw (fun () ->
            Eio.Cancel.sub (fun cc ->
                match
                  Eio.Switch.run (fun owned ->
                      let exporter =
                        make ~caps ~sw:owned ~client ~endpoint ~clock ~budget ()
                      in
                      Eio.Promise.resolve open_ (exporter, cc);
                      Eio.Promise.await hold)
                with
                | () -> ()
                | exception Eio.Cancel.Cancelled _ -> ()))
      in
      let exporter, cc = Eio.Promise.await opened in
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"uncertain" ()) 7.;
      let flushed = fork_result ~sw (fun () -> O.flush exporter) in
      let target, body = Eio.Stream.take arrivals in
      Alcotest.(check bool)
        "Flush owns metric export" true
        (String.starts_with ~prefix:"POST /v1/metrics " target);
      Eio.Cancel.cancel cc Exit;
      guard env "owner recovery" owner_done;
      let _, recovered = Eio.Stream.take arrivals in
      Alcotest.(check string) "uncertain window recovered" body recovered;
      ok (guard env "consumed Flush" flushed))

let automatic_budget ~caps () =
  (* ^notel-056b ^notel-jx0z ^notel-48tm ^notel-s12c: automatic release owns the same
     terminal result and budget, without protecting cancellation of joining callers. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let created, ready = Eio.Promise.create () in
      let ending =
        fork_result ~sw (fun () ->
            Eio.Switch.run (fun owned ->
                let exporter = make ~caps ~sw:owned ~client ~endpoint ~clock ~budget () in
                Eio.Promise.resolve ready exporter;
                Eio.Switch.on_release owned (fun () ->
                    L.info (logger env exporter) "last")))
      in
      let exporter = Eio.Promise.await created in
      ignore (Eio.Stream.take arrivals : string * string);
      let entered, enter = Eio.Promise.create () in
      let cancelled, cancel_seen = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Cancel.sub (fun cc ->
              Eio.Promise.resolve enter cc;
              match O.shutdown exporter with
              | exception Eio.Cancel.Cancelled _ -> Eio.Promise.resolve cancel_seen ()
              | _ -> Alcotest.fail "release waiter cancellation was swallowed"));
      let cc = Eio.Promise.await entered in
      Eio.Fiber.yield ();
      Eio.Cancel.cancel cc Exit;
      guard env "automatic-release waiter cancellation" cancelled;
      let joined = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Fiber.yield ();
      advance clock;
      guard env "automatic release" ending;
      Alcotest.(check bool)
        "shutdown joins automatic release's deadline" true
        (guard env "shutdown during automatic release" joined = Error `Drain_deadline);
      Alcotest.(check bool)
        "shutdown after automatic release keeps deadline" true
        (O.shutdown exporter = Error `Drain_deadline))

let retires_worker ~caps () =
  (* ^notel-m8ax: an idle worker's mock-clock wake-up is still observable after Stop,
     even though closed metric admission means this is not a post-shutdown send leak. *)
  with_collector (fun _env sw client endpoint clock _arrivals _release ->
      let exporter = make ~caps ~sw ~client ~endpoint ~clock ~budget () in
      ok (O.shutdown exporter);
      Eio.Fiber.yield ();
      Alcotest.(check bool)
        "ending leaves no worker timer" false
        (Eio_mock.Clock.try_advance clock))

let preseal_flush ~caps () =
  (* ^notel-5qi9 ^notel-d52a: a Flush blocked before admission wakes at ending expiry. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let exporter = make ~caps ~sw ~client ~endpoint ~clock ~budget () in
      let log = logger env exporter in
      L.info log "in flight";
      ignore (Eio.Stream.take arrivals : string * string);
      L.info log "queued";
      let flushed = fork_result ~sw (fun () -> O.flush exporter) in
      Eio.Fiber.yield ();
      ignore
        (fork_result ~sw (fun () -> O.shutdown exporter)
          : (unit, O.error) result Eio.Promise.t);
      Eio.Fiber.yield ();
      Eio.Fiber.yield ();
      advance clock;
      match guard env "pre-seal Flush" flushed with
      | Error `Drain_deadline -> ()
      | result ->
          ignore (ok result : unit);
          Alcotest.fail "expected recorded deadline")

let global_deadline ~caps () =
  (* ^notel-056b ^notel-jx0z ^notel-s12c: completing a request and adding another
     shutdown waiter must not buy another ending budget. *)
  let second, release_second = Eio.Promise.create () in
  Fun.protect
    ~finally:(fun () -> ignore (Eio.Promise.try_resolve release_second () : bool))
    (fun () ->
      with_collector ~mock_http_clock:true
        ~before_reply:(fun index -> if index = 2 then Eio.Promise.await second)
        (fun env sw client endpoint clock arrivals release ->
          let exporter =
            make ~request_deadline:(Ox.Duration.seconds 2) ~caps ~sw ~client ~endpoint
              ~clock ~budget ()
          in
          let log = logger env exporter in
          L.info log "first";
          ignore (Eio.Stream.take arrivals : string * string);
          L.info log "second";
          let first = fork_result ~sw (fun () -> O.shutdown exporter) in
          Eio.Fiber.yield ();
          Eio_mock.Clock.set_time clock 0.020;
          Eio.Promise.resolve release ();
          ignore (Eio.Stream.take arrivals : string * string);
          let later = fork_result ~sw (fun () -> O.shutdown exporter) in
          Eio_mock.Clock.set_time clock 0.031;
          let deadline result =
            match result with
            | Error `Drain_deadline -> ()
            | _ -> Alcotest.fail "terminal result was not the total deadline"
          in
          deadline (guard env "first terminal waiter" first);
          deadline (guard env "later terminal waiter" later);
          deadline (O.shutdown exporter);
          Alcotest.(check int)
            "only uncertain second batch is abandoned" 1 (O.abandoned exporter).logs))

let accounting ~caps () =
  (* ^notel-od2q ^notel-d52a ^notel-5qi9: expiration accounts for bounded retained
     data and admitted controls, settles those controls, and rejects later admission. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let exporter = make ~max_queue:3 ~caps ~sw ~client ~endpoint ~clock ~budget () in
      let log = logger env exporter in
      L.info log "uncertain";
      ignore (Eio.Stream.take arrivals : string * string);
      ignore (L.span log "queued span" (fun () -> Ok ()) : (unit, string) result);
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"queued metric" ()) 9.;
      let flush = fork_result ~sw (fun () -> O.flush exporter) in
      Eio.Fiber.yield ();
      let stop = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Fiber.yield ();
      advance clock;
      let deadline = function
        | Error `Drain_deadline -> ()
        | _ -> Alcotest.fail "expected the recorded deadline"
      in
      deadline (guard env "accounting shutdown" stop);
      deadline (guard env "admitted accounting Flush" flush);
      let counts = O.abandoned exporter in
      Alcotest.(check int) "uncertain log" 1 counts.logs;
      Alcotest.(check int) "queued trace" 1 counts.spans;
      Alcotest.(check int) "metric window" 1 counts.metric_series;
      Alcotest.(check int) "admitted Flush" 1 counts.controls;
      Alcotest.(check int) "expiry is not a queue drop" 0 (O.dropped exporter);
      L.info log "after ending";
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"late metric" ()) 1.;
      Alcotest.(check bool) "new Flush is closed" true (O.flush exporter = Error `Closed);
      deadline (O.shutdown exporter);
      Alcotest.(check bool) "counts stay immutable" true (counts = O.abandoned exporter);
      Eio.Fiber.yield ();
      Alcotest.(check int) "no sends after ending" 0 (Eio.Stream.length arrivals))

let queued_controls_recovery ~caps () =
  (* ^notel-d52a ^notel-opp7 ^notel-g1e1: recover mixed data with both a pending
     batch-overflow Flush and a queued Flush; retain neither a lost nor duplicate resolver. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      let opened, open_ = Eio.Promise.create () in
      let hold, _ = Eio.Promise.create () in
      let owner =
        fork_result ~sw (fun () ->
            Eio.Cancel.sub (fun cc ->
                match
                  Eio.Switch.run (fun owned ->
                      let exporter =
                        make ~batch_size:2 ~max_queue:4 ~caps ~sw:owned ~client ~endpoint
                          ~clock ~budget ()
                      in
                      Eio.Promise.resolve open_ (exporter, cc);
                      Eio.Promise.await hold)
                with
                | () -> ()
                | exception Eio.Cancel.Cancelled _ -> ()))
      in
      let exporter, cc = Eio.Promise.await opened in
      let log = logger env exporter in
      L.info log "uncertain mixed batch";
      let pending = fork_result ~sw (fun () -> O.flush exporter) in
      let _, first_body = Eio.Stream.take arrivals in
      ignore (L.span log "recovered span" (fun () -> Ok ()) : (unit, string) result);
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"recovered metric" ()) 4.;
      let queued = fork_result ~sw (fun () -> O.flush exporter) in
      Eio.Fiber.yield ();
      Eio.Cancel.cancel cc Exit;
      guard env "mixed owner recovery" owner;
      ok (guard env "pending Flush" pending);
      ok (guard env "queued Flush" queued);
      ok (O.shutdown exporter);
      let _, repeated_body = Eio.Stream.take arrivals in
      Alcotest.(check string) "uncertain logs repeated unchanged" first_body repeated_body;
      let trace, _ = Eio.Stream.take arrivals in
      let metric, _ = Eio.Stream.take arrivals in
      Alcotest.(check bool)
        "trace recovered" true
        (String.starts_with ~prefix:"POST /v1/traces " trace);
      Alcotest.(check bool)
        "metric recovered" true
        (String.starts_with ~prefix:"POST /v1/metrics " metric);
      Alcotest.(check int)
        "no work abandoned on recovery" 0 (O.abandoned exporter).controls)

let hooks_and_terminal_failure ~caps () =
  (* ^notel-s12c ^notel-d52a ^notel-nf92: a parking summary cannot retain the
     worker or steal a failure; the independent signal hook also remains best effort. *)
  with_collector ~response:"HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\n\r\n"
    (fun env sw client endpoint clock arrivals release ->
      let never, _ = Eio.Promise.create () in
      let calls = ref 0 in
      let exporter =
        make
          ~on_error:(fun _ -> Eio.Promise.await never)
          ~on_signal_error:(fun _ _ ->
            incr calls;
            failwith "summary defect")
          ~caps ~sw ~client ~endpoint ~clock ~budget ()
      in
      L.info (logger env exporter) "refused";
      ignore (Eio.Stream.take arrivals : string * string);
      let first = fork_result ~sw (fun () -> O.shutdown exporter) in
      let second = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Promise.resolve release ();
      List.iter
        (fun result ->
          Alcotest.(check bool) "same typed refusal" true (result = Error (`Status 503)))
        [
          guard env "first refusal waiter" first;
          guard env "second refusal waiter" second;
          O.shutdown exporter;
        ];
      Alcotest.(check int) "independent signal hook invoked" 1 !calls;
      Eio.Fiber.yield ();
      Alcotest.(check bool)
        "refusal ending retires worker" false
        (Eio_mock.Clock.try_advance clock))

let private_diagnostics ~caps () =
  (* ^notel-nf92: raw peer headers and malformed body text are absent even when
     a consumer inspects the typed HTTP payload instead of using exporter pp_error. *)
  let header_secret = "collector-header-secret" in
  let body_secret = "collector-body-secret" in
  let response =
    Printf.sprintf
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Secret: %s\r\n\r\n%s\r\n"
      header_secret body_secret
  in
  with_collector ~response (fun env sw client endpoint clock arrivals release ->
      let callbacks = ref [] in
      let exporter =
        make
          ~on_error:(fun error -> callbacks := error :: !callbacks)
          ~caps ~sw ~client ~endpoint ~clock ~budget ()
      in
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"private" ()) 2.;
      let flush = fork_result ~sw (fun () -> O.flush exporter) in
      ignore (Eio.Stream.take arrivals : string * string);
      Eio.Promise.resolve release ();
      let error =
        match guard env "private failure" flush with
        | Error error -> error
        | Ok () -> Alcotest.fail "malformed body accepted"
      in
      (match error with
      | `Http (`Body failure) -> (
          Alcotest.(check int) "collector headers removed" 0 (List.length failure.headers);
          match failure.reason with
          | `Malformed reason ->
              Alcotest.(check string)
                "safe body summary" "malformed collector body" reason
          | _ -> Alcotest.fail "expected malformed body classification")
      | _ -> Alcotest.fail "expected HTTP body failure");
      Alcotest.(check bool)
        "callback receives same sanitized result" true (!callbacks = [ error ]);
      let summary = Format.asprintf "%a" O.pp_error error in
      Alcotest.(check string) "safe diagnostic" "OTLP HTTP transport failed" summary;
      ok (O.shutdown exporter))

let invalid_budget ~caps () =
  (* ^notel-056b: construction requires an explicit positive finite ending budget. *)
  with_collector (fun _env sw client endpoint clock _arrivals _release ->
      match
        O.create ~caps ~sw ~http_client:client ~endpoint ~clock ~service_name:"ending"
          ~ending_budget:Ox.Duration.zero ()
      with
      | Error (`Invalid_config _) -> ()
      | _ -> Alcotest.fail "zero ending budget accepted")

let worker_defect_recovery ~caps () =
  (* ^notel-d52a ^notel-g1e1: a worker defect stays a switch defect, while later
     shutdown observes bounded recovery rather than a retired worker's lost command. *)
  with_collector (fun env sw client endpoint clock arrivals release ->
      let armed = ref false in
      let module Clock = struct
        type t = unit
        type time = float

        let now () =
          if !armed then (
            armed := false;
            failwith "worker clock defect")
          else Eio.Time.now clock

        let sleep_until () time = Eio.Time.sleep_until clock time
      end in
      let observed = Eio.Resource.T ((), Eio.Time.Pi.clock (module Clock)) in
      let opened, open_ = Eio.Promise.create () in
      let hold, _ = Eio.Promise.create () in
      let owner =
        fork_result ~sw (fun () ->
            match
              Eio.Switch.run (fun owned ->
                  let exporter =
                    make ~caps ~sw:owned ~client ~endpoint ~clock:observed ~budget ()
                  in
                  Eio.Promise.resolve open_ exporter;
                  Eio.Promise.await hold)
            with
            | () -> Alcotest.fail "worker defect disappeared"
            | exception Failure reason ->
                Alcotest.(check string) "defect preserved" "worker clock defect" reason)
      in
      let exporter = Eio.Promise.await opened in
      L.info (logger env exporter) "before defect";
      ignore (Eio.Stream.take arrivals : string * string);
      O.Meter.add (O.Meter.counter (O.meter exporter) ~name:"after defect" ()) 3.;
      armed := true;
      Eio.Promise.resolve release ();
      guard env "failed-worker owner recovery" owner;
      ok (O.shutdown exporter);
      let target, _ = Eio.Stream.take arrivals in
      Alcotest.(check bool)
        "metric recovered after worker defect" true
        (String.starts_with ~prefix:"POST /v1/metrics " target))

let request_deadline ~caps () =
  (* ^notel-g1e1: the request's shorter deadline remains a typed transport timeout,
     independently of a longer total ending budget, on the same controlled clock. *)
  with_collector ~mock_http_clock:true
    (fun env sw client endpoint clock arrivals _release ->
      let exporter =
        make ~request_deadline:(Ox.Duration.ms 10) ~caps ~sw ~client ~endpoint ~clock
          ~budget ()
      in
      L.info (logger env exporter) "send timeout";
      ignore (Eio.Stream.take arrivals : string * string);
      let ending = fork_result ~sw (fun () -> O.shutdown exporter) in
      Eio.Fiber.yield ();
      Eio_mock.Clock.set_time clock 0.011;
      let result = guard env "request deadline independently" ending in
      Alcotest.(check bool)
        "request timeout is not ending expiry" true
        (result = Error (`Http `Timeout));
      Alcotest.(check bool)
        "request timeout remains terminal" true
        (result = O.shutdown exporter);
      Alcotest.(check int)
        "confirmed transport timeout is not abandoned" 0 (O.abandoned exporter).logs)

let private_headers_and_transport ~caps () =
  (* ^notel-nf92: construction and both HTTP response phases retain useful classifiers
     without request secrets, response headers, or peer body text in callback data. *)
  with_collector (fun env sw client endpoint clock arrivals _release ->
      List.iter
        (fun headers ->
          let callbacks = ref [] in
          let exporter =
            O.create ~caps ~sw ~clock ~http_client:client ~endpoint ~service_name:"ending"
              ~ending_budget:budget ~headers
              ~on_error:(fun error -> callbacks := error :: !callbacks)
              ()
            |> ok
          in
          L.info (logger env exporter) "invalid private headers";
          let ending = fork_result ~sw (fun () -> O.shutdown exporter) in
          let result = guard env "invalid-header diagnostics" ending in
          Alcotest.(check bool)
            "safe invalid-header classifier" true
            (result = Error (`Http (`Protocol "invalid HTTP exchange")));
          Alcotest.(check bool)
            "sanitized invalid-header callback" true
            (!callbacks = [ `Http (`Protocol "invalid HTTP exchange") ]))
        [
          [ ("authorization", "Bearer secret\r\nraw-secret") ];
          [ ("malformed header secret", "raw-secret") ];
        ];
      Alcotest.(check int)
        "invalid private headers never sent" 0 (Eio.Stream.length arrivals));
  List.iter
    (fun (label, response, valid) ->
      with_collector ~response (fun env sw client endpoint clock arrivals release ->
          let callbacks = ref [] in
          let exporter =
            make
              ~on_error:(fun error -> callbacks := error :: !callbacks)
              ~caps ~sw ~client ~endpoint ~clock ~budget ()
          in
          L.info (logger env exporter) "private phases";
          ignore (Eio.Stream.take arrivals : string * string);
          let ending = fork_result ~sw (fun () -> O.shutdown exporter) in
          Eio.Promise.resolve release ();
          let error =
            match guard env label ending with
            | Error error -> error
            | Ok () -> Alcotest.fail "invalid response accepted"
          in
          Alcotest.(check bool) label true (valid error);
          Alcotest.(check bool) "sanitized callback payload" true (!callbacks = [ error ]);
          Alcotest.(check bool)
            "same terminal failure" true
            (O.shutdown exporter = Error error)))
    [
      ( "pre-head private protocol",
        "HTTP/1.1 peer-secret invalid\r\n\r\n",
        function `Http (`Protocol "invalid HTTP exchange") -> true | _ -> false );
      ( "post-head private truncation",
        "HTTP/1.1 200 OK\r\n\
         Content-Length: 1000\r\n\
         X-Secret: header-secret\r\n\
         \r\n\
         body-secret",
        function
        | `Http (`Body { headers = []; reason = `Truncated; _ }) -> true
        | _ -> false );
      ( "private collector refusal",
        "HTTP/1.1 503 Refused\r\n\
         Content-Length: 11\r\n\
         X-Secret: header-secret\r\n\
         \r\n\
         body-secret",
        function `Status 503 -> true | _ -> false );
    ]

let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.random >) in
  Alcotest.run "OTLP ending"
    [
      ( "reproduction",
        [
          Alcotest.test_case "full queue budget (^notel-056b ^notel-jx0z)" `Quick
            (full_queue_budget ~caps);
          Alcotest.test_case "cancelled shutdown (^notel-48tm ^notel-s12c)" `Quick
            (cancelled_shutdown ~caps);
          Alcotest.test_case "consumed Flush (^notel-hjd5 ^notel-d52a ^notel-opp7)" `Quick
            (consumed_flush ~caps);
          Alcotest.test_case
            "automatic budget (^notel-056b ^notel-jx0z ^notel-48tm ^notel-s12c)" `Quick
            (automatic_budget ~caps);
          Alcotest.test_case "worker retirement (^notel-m8ax)" `Quick
            (retires_worker ~caps);
          Alcotest.test_case "pre-seal Flush (^notel-5qi9 ^notel-d52a)" `Quick
            (preseal_flush ~caps);
        ] );
      ( "ending contract",
        [
          Alcotest.test_case "independent request deadline (^notel-g1e1)" `Quick
            (request_deadline ~caps);
          Alcotest.test_case "private headers and transport phases (^notel-nf92)" `Quick
            (private_headers_and_transport ~caps);
          Alcotest.test_case
            "one absolute terminal deadline (^notel-056b ^notel-jx0z ^notel-s12c)" `Quick
            (global_deadline ~caps);
          Alcotest.test_case "bounded abandonment (^notel-od2q ^notel-d52a ^notel-5qi9)"
            `Quick (accounting ~caps);
          Alcotest.test_case
            "pending and queued controls recover (^notel-d52a ^notel-opp7 ^notel-g1e1)"
            `Quick
            (queued_controls_recovery ~caps);
          Alcotest.test_case
            "nonparking summaries preserve terminal refusal (^notel-s12c ^notel-d52a \
             ^notel-nf92)"
            `Quick
            (hooks_and_terminal_failure ~caps);
          Alcotest.test_case "private typed diagnostics (^notel-nf92)" `Quick
            (private_diagnostics ~caps);
          Alcotest.test_case "explicit positive budget (^notel-056b)" `Quick
            (invalid_budget ~caps);
          Alcotest.test_case "failed worker recovers (^notel-d52a ^notel-g1e1)" `Quick
            (worker_defect_recovery ~caps);
        ] );
    ]
