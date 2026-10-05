module T = Ox_ai.Transport

let run f =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 2. (fun () ->
          Eio.Switch.run (fun sw -> f ~sw env)))

let post ~sw env server ?clock ?(deadline = Ox.Duration.seconds 1) ?timeout ?max_attempts
    ?replay_policy () =
  let clock = Option.value clock ~default:env#clock in
  let http = Ox_http.Client.create ~sw ~net:env#net ~clock () in
  let memory = Ox_observability.Logger.Memory.create () in
  let logger =
    Ox_observability.Logger.create ~service:"replay_test" ~clock:env#clock
      ~mono_clock:env#mono_clock
      ~reporter:(Ox_observability.Logger.Memory.reporter memory)
      ()
  in
  T.post_json ~http ~clock ~logger ~deadline ?timeout ?max_attempts ?replay_policy
    ~endpoint:server.Retry_server.endpoint ~authorization:[] ~body:(Bytes.of_string "{}")
    ()

let unavailable = function
  | Error (`Unavailable _) -> ()
  | Error error -> Alcotest.failf "expected Unavailable: %s" (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.fail "lost reply unexpectedly succeeded"

let lost_reply () =
  (* ^safe-o2b6 ^safe-3o27: a committed effect survives a severed response. *)
  run (fun ~sw env ->
      let server = Retry_server.start ~sw ~net:env#net [ Retry_server.Lose_reply ] in
      unavailable (post ~sw env server ());
      Alcotest.(check int) "^safe-3o27 default commits once" 1 !(server.effects);
      Alcotest.(check int) "^safe-o2b6 default sends once" 1 !(server.requests))

let duplicate_effect_consent () =
  (* ^safe-o2b6 ^safe-a5mq: consent allows duplicates; it is not idempotency proof. *)
  run (fun ~sw env ->
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Lose_reply; Retry_server.Reply 200 ]
      in
      (match post ~sw env server ~replay_policy:T.Allow_duplicate_effects () with
      | Ok { status = 200; body } ->
          Alcotest.(check bytes) "reply" (Bytes.of_string "{}") body
      | Ok _ -> Alcotest.fail "wrong status"
      | Error error -> Alcotest.failf "not recovered: %s" (Ox_ai.Error.to_string error));
      Alcotest.(check int)
        "^safe-o2b6 explicit consent duplicates effects" 2 !(server.effects);
      Alcotest.(check int)
        "^safe-a5mq two requests, not deduplicated" 2 !(server.requests))

let before_commit () =
  (* ^safe-a5mq ^safe-3o27: the same transport failure can precede commit.
     The client cannot distinguish it from a lost reply, so refuses repetition. *)
  run (fun ~sw env ->
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Before_commit; Retry_server.Reply 200 ]
      in
      unavailable (post ~sw env server ());
      Alcotest.(check int) "^safe-3o27 nothing committed" 0 !(server.effects);
      Alcotest.(check int) "^safe-a5mq no speculative second request" 1 !(server.requests))

let budgets_are_not_permission () =
  (* ^safe-s51t: a large budget cannot opt a caller into replay. *)
  run (fun ~sw env ->
      let server = Retry_server.start ~sw ~net:env#net [ Retry_server.Lose_reply ] in
      unavailable (post ~sw env server ~max_attempts:5 ());
      Alcotest.(check int) "^safe-s51t budget alone commits once" 1 !(server.effects);
      Alcotest.(check int) "^safe-s51t budget alone sends once" 1 !(server.requests))

let refusal_statuses () =
  (* ^safe-a5mq: 429/529 alone are not evidence of non-commit. *)
  List.iter
    (fun status ->
      run (fun ~sw env ->
          let server =
            Retry_server.start ~sw ~net:env#net [ Retry_server.Reply status ]
          in
          (match post ~sw env server () with
          | Error (`Unavailable { retryable = true; status = Some got; _ }) ->
              Alcotest.(check int) "^safe-a5mq classification unchanged" status got
          | _ -> Alcotest.fail "refusal status changed classification");
          Alcotest.(check int)
            "^safe-a5mq status does not prove non-commit" 1 !(server.effects);
          Alcotest.(check int)
            "^safe-a5mq status does not authorize replay" 1 !(server.requests)))
    [ 429; 529 ]

let exhausted_bound () =
  (* ^safe-s51t ^safe-3o27: consenting callers still respect the ceiling and
     propagate the final attempt's failure, not a stale earlier verdict. *)
  List.iter
    (fun attempts ->
      run (fun ~sw env ->
          let server =
            Retry_server.start ~sw ~net:env#net
              (List.init attempts (fun n ->
                   if n = attempts - 1 then Retry_server.Truncate_reply
                   else Retry_server.Lose_reply))
          in
          (match
             post ~sw env server ~max_attempts:attempts
               ~replay_policy:T.Allow_duplicate_effects ()
           with
          | Error (`Unavailable { status = Some 200; _ }) -> ()
          | _ -> Alcotest.fail "did not propagate final truncated-body failure");
          Alcotest.(check int)
            "^safe-s51t exhausted attempt ceiling" attempts !(server.requests);
          Alcotest.(check int)
            "^safe-3o27 consent can duplicate committed effects" attempts
            !(server.effects)))
    [ 1; 3 ]

let timeout_after_commit () =
  (* ^safe-3o27: advance a mock clock only after the server confirms commit. *)
  run (fun ~sw env ->
      let clock = Eio_mock.Clock.make () in
      let server = Retry_server.start ~sw ~net:env#net [ Retry_server.Withhold_reply ] in
      Eio.Fiber.both
        (fun () ->
          Eio.Promise.await server.committed;
          Eio_mock.Clock.set_time clock 0.051)
        (fun () ->
          match
            post ~sw env server
              ~clock:(clock :> _ Eio.Time.clock_ty Eio.Resource.t)
              ~timeout:(Ox.Duration.ms 50) ()
          with
          | Error `Timeout -> ()
          | _ -> Alcotest.fail "^safe-3o27 timeout classification changed");
      Eio.Promise.await server.closed;
      Alcotest.(check int)
        "^safe-3o27 timeout after commit never replays" 1 !(server.effects);
      Alcotest.(check int) "^safe-o2b6 only one timed-out request" 1 !(server.requests))

let backoff_clock clock entered =
  (* Clock instrumentation only drives time; assertions stay at post_json and the peer. *)
  let module Provider = struct
    type t = unit
    type time = float

    let now () = Eio.Time.now clock

    let sleep_until () due =
      if abs_float (due -. now () -. Ox.Duration.to_seconds_float T.backoff) < 1e-9 then
        Eio.Promise.resolve entered ();
      Eio.Time.sleep_until clock due
  end in
  Eio.Resource.T ((), Eio.Time.Pi.clock (module Provider))

let deadline_during_backoff () =
  (* ^safe-s51t ^safe-3o27: consent and a large ceiling cannot exceed the whole deadline. *)
  run (fun ~sw env ->
      let clock = Eio_mock.Clock.make () in
      let entered, enter = Eio.Promise.create () in
      let observed = backoff_clock clock enter in
      let server = Retry_server.start ~sw ~net:env#net [ Retry_server.Lose_reply ] in
      Eio.Fiber.both
        (fun () ->
          Eio.Promise.await entered;
          Eio_mock.Clock.set_time clock 0.051)
        (fun () ->
          match
            post ~sw env server ~clock:observed ~deadline:(Ox.Duration.ms 50)
              ~timeout:(Ox.Duration.seconds 1) ~max_attempts:5
              ~replay_policy:T.Allow_duplicate_effects ()
          with
          | Error `Timeout -> ()
          | _ -> Alcotest.fail "^safe-s51t whole deadline did not stop backoff");
      Alcotest.(check int)
        "^safe-s51t no replay after whole deadline" 1 !(server.requests);
      Alcotest.(check int)
        "^safe-3o27 first effect survives whole deadline" 1 !(server.effects))

let cancellation_after_commit () =
  (* ^safe-3o27: neither replay policy translates external cancellation to Timeout. *)
  List.iter
    (fun replay_policy ->
      run (fun ~sw env ->
          let server =
            Retry_server.start ~sw ~net:env#net [ Retry_server.Withhold_reply ]
          in
          let propagated = ref false in
          Eio.Cancel.sub (fun cc ->
              Eio.Fiber.both
                (fun () ->
                  Eio.Promise.await server.committed;
                  Eio.Cancel.cancel cc Exit)
                (fun () ->
                  match post ~sw env server ~replay_policy () with
                  | _ -> Alcotest.fail "^safe-3o27 cancellation became a result"
                  | exception Eio.Cancel.Cancelled Exit -> propagated := true));
          Alcotest.(check bool) "^safe-3o27 original cancellation reason" true !propagated;
          Eio.Promise.await server.closed;
          Alcotest.(check int)
            "^safe-3o27 cancelled committed effect remains" 1 !(server.effects);
          Alcotest.(check int)
            "^safe-o2b6 cancellation never replays" 1 !(server.requests)))
    [ T.Never_replay; T.Allow_duplicate_effects ]

let cancellation_during_backoff () =
  (* ^safe-s51t: explicit consent does not mask cancellation during scheduling. *)
  run (fun ~sw env ->
      let clock = Eio_mock.Clock.make () in
      let entered, enter = Eio.Promise.create () in
      let server = Retry_server.start ~sw ~net:env#net [ Retry_server.Lose_reply ] in
      let propagated = ref false in
      Eio.Cancel.sub (fun cc ->
          Eio.Fiber.both
            (fun () ->
              Eio.Promise.await entered;
              Eio.Cancel.cancel cc Exit)
            (fun () ->
              match
                post ~sw env server ~clock:(backoff_clock clock enter)
                  ~replay_policy:T.Allow_duplicate_effects ()
              with
              | _ -> Alcotest.fail "^safe-s51t backoff cancellation became a result"
              | exception Eio.Cancel.Cancelled Exit -> propagated := true));
      Alcotest.(check bool) "^safe-s51t backoff propagates cancellation" true !propagated;
      Alcotest.(check int)
        "^safe-s51t cancellation stops another request" 1 !(server.requests);
      Alcotest.(check int)
        "^safe-3o27 cancellation cannot undo commit" 1 !(server.effects))

let consent_preserves_candidates () =
  (* ^safe-s51t: permission does not expand the existing failure candidates. *)
  List.iter
    (fun status ->
      run (fun ~sw env ->
          let server =
            Retry_server.start ~sw ~net:env#net
              [ Retry_server.Reply status; Retry_server.Reply 200 ]
          in
          let result = post ~sw env server ~replay_policy:T.Allow_duplicate_effects () in
          let attempts = if status = 429 || status = 529 then 2 else 1 in
          (match (status, result) with
          | (429 | 529), Ok { status = 200; _ }
          | 401, Error (`Authentication _)
          | 500, Error (`Unavailable { status = Some 500; retryable = false; _ }) ->
              ()
          | _ -> Alcotest.fail "^safe-s51t consent changed failure eligibility");
          Alcotest.(check int)
            "^safe-s51t eligible candidates only" attempts !(server.requests);
          Alcotest.(check int) "^safe-o2b6 actual effect count" attempts !(server.effects)))
    [ 429; 529; 401; 500 ]

let timeout_duplicate_consent () =
  (* ^safe-o2b6 ^safe-3o27: an opted-in timeout-after-commit duplicates, not deduplicates. *)
  run (fun ~sw env ->
      let clock = Eio_mock.Clock.make () in
      let entered, enter = Eio.Promise.create () in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Withhold_reply; Retry_server.Reply 200 ]
      in
      Eio.Fiber.both
        (fun () ->
          Eio.Promise.await server.committed;
          Eio_mock.Clock.set_time clock 0.051;
          Eio.Promise.await entered;
          Eio_mock.Clock.set_time clock 0.152)
        (fun () ->
          match
            post ~sw env server ~clock:(backoff_clock clock enter)
              ~timeout:(Ox.Duration.ms 50) ~replay_policy:T.Allow_duplicate_effects ()
          with
          | Ok { status = 200; _ } -> ()
          | _ -> Alcotest.fail "^safe-3o27 consent did not recover a timed-out request");
      Eio.Promise.await server.closed;
      Alcotest.(check int) "^safe-3o27 timeout consent commits twice" 2 !(server.effects);
      Alcotest.(check int) "^safe-o2b6 timeout consent sends twice" 2 !(server.requests))

let () =
  Alcotest.run "POST replay safety"
    [
      ( "replay",
        [
          Alcotest.test_case "^safe-o2b6 ^safe-3o27 lost reply" `Quick lost_reply;
          Alcotest.test_case "^safe-o2b6 ^safe-a5mq duplicate-effect consent" `Quick
            duplicate_effect_consent;
          Alcotest.test_case "^safe-a5mq ^safe-3o27 failure before commit" `Quick
            before_commit;
          Alcotest.test_case "^safe-s51t budget is not replay permission" `Quick
            budgets_are_not_permission;
          Alcotest.test_case "^safe-a5mq 429/529 do not prove non-commit" `Quick
            refusal_statuses;
          Alcotest.test_case "^safe-s51t ^safe-3o27 exhausted attempt bound" `Quick
            exhausted_bound;
          Alcotest.test_case "^safe-3o27 timeout after commit" `Quick timeout_after_commit;
          Alcotest.test_case "^safe-s51t ^safe-3o27 whole deadline during backoff" `Quick
            deadline_during_backoff;
          Alcotest.test_case "^safe-3o27 cancellation after commit" `Quick
            cancellation_after_commit;
          Alcotest.test_case "^safe-s51t cancellation during backoff" `Quick
            cancellation_during_backoff;
          Alcotest.test_case "^safe-s51t consent preserves candidates" `Quick
            consent_preserves_candidates;
          Alcotest.test_case "^safe-o2b6 ^safe-3o27 timeout duplicate consent" `Quick
            timeout_duplicate_consent;
        ] );
    ]
