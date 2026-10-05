module T = Ox_ai.Transport

type client = Systemone | Chat

let run f =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 2. (fun () ->
          Eio.Switch.run (fun sw -> f ~sw env)))

let call client ~sw env server ~clock ?replay_policy ?timeout
    ?(deadline = Ox.Duration.seconds 1) () =
  let http = Ox_http.Client.create ~sw ~net:env#net ~clock () in
  let memory = Ox_observability.Logger.Memory.create () in
  let logger =
    Ox_observability.Logger.create ~service:"client_replay_test" ~clock:env#clock
      ~mono_clock:env#mono_clock
      ~reporter:(Ox_observability.Logger.Memory.reporter memory)
      ()
  in
  let api_key = Ox_observability.Redact.make "local-test-only" in
  let endpoint = server.Retry_server.endpoint in
  match client with
  | Systemone ->
      let client =
        Ox_ai_systemone.Client.create ~http ~clock ~logger ~endpoint ~api_key
          ~model:"test-model" ?replay_policy ?timeout ()
      in
      Result.map
        (fun _ -> ())
        (Ox_ai_systemone.Client.evaluate client ~deadline ~state:`Null ~questions:[])
  | Chat ->
      let client =
        Ox_ai_chat.create ~http ~clock ~logger ~endpoint ~api_key ?replay_policy ?timeout
          ()
      in
      Result.map
        (fun _ -> ())
        (Ox_ai_chat.complete client ~deadline ~model:"test-model" ~messages:[] ())

let advancing_clock clock =
  let module Provider = struct
    type t = unit
    type time = float

    let now () = Eio.Time.now clock

    let sleep_until () due =
      if abs_float (due -. now () -. Ox.Duration.to_seconds_float T.backoff) < 1e-9 then
        Eio_mock.Clock.set_time clock due;
      Eio.Time.sleep_until clock due
  end in
  Eio.Resource.T ((), Eio.Time.Pi.clock (module Provider))

let authentication = function
  | Error (`Authentication _) -> ()
  | Error error ->
      Alcotest.failf "expected final Authentication: %s" (Ox_ai.Error.to_string error)
  | Ok () -> Alcotest.fail "expected final Authentication"

let consent_duplicates client () =
  (* ^safe-o2b6 ^safe-a5mq ^safe-3o27: consent permits a second remote execution,
     not deduplication. The second reply's final typed error must reach the caller. *)
  run (fun ~sw env ->
      let clock = advancing_clock (Eio_mock.Clock.make ()) in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Lose_reply; Retry_server.Reply 401 ]
      in
      authentication
        (call client ~sw env server ~clock ~replay_policy:T.Allow_duplicate_effects ());
      Alcotest.(check int) "^safe-o2b6 consent sends twice" 2 !(server.requests);
      Alcotest.(check int) "^safe-3o27 acknowledged duplicate effects" 2 !(server.effects))

let default_once client () =
  (* ^safe-o2b6 ^safe-3o27: a committed, lost reply is not permission to repeat. *)
  run (fun ~sw env ->
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Lose_reply; Retry_server.Reply 401 ]
      in
      (match call client ~sw env server ~clock:env#clock () with
      | Error (`Unavailable _) -> ()
      | _ -> Alcotest.fail "default must preserve Unavailable");
      Alcotest.(check int) "^safe-o2b6 default sends once" 1 !(server.requests);
      Alcotest.(check int) "^safe-3o27 default commits once" 1 !(server.effects))

let before_commit client () =
  (* ^safe-o2b6 ^safe-3o27: consent also reaches transport for pre-commit failure. *)
  run (fun ~sw env ->
      let clock = advancing_clock (Eio_mock.Clock.make ()) in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Before_commit; Retry_server.Reply 401 ]
      in
      authentication
        (call client ~sw env server ~clock ~replay_policy:T.Allow_duplicate_effects ());
      Alcotest.(check int) "^safe-o2b6 two attempts" 2 !(server.requests);
      Alcotest.(check int) "^safe-3o27 only second attempt committed" 1 !(server.effects))

let attempt_timeout client () =
  (* ^safe-3o27 ^safe-s51t: timeout after commit can duplicate only with consent;
     advance virtual time after the peer's commit, with enough whole-call budget. *)
  run (fun ~sw env ->
      let virtual_clock = Eio_mock.Clock.make () in
      let clock = advancing_clock virtual_clock in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Withhold_reply; Retry_server.Reply 401 ]
      in
      Eio.Fiber.both
        (fun () ->
          Eio.Promise.await server.committed;
          Eio_mock.Clock.set_time virtual_clock 0.051)
        (fun () ->
          authentication
            (call client ~sw env server ~clock ~timeout:(Ox.Duration.ms 50)
               ~replay_policy:T.Allow_duplicate_effects ()));
      Eio.Promise.await server.closed;
      Alcotest.(check int) "^safe-s51t timeout retry within budget" 2 !(server.requests);
      Alcotest.(check int)
        "^safe-3o27 timeout consent duplicates effects" 2 !(server.effects))

let deadline_stops_replay client () =
  (* ^safe-s51t: explicit consent cannot extend the whole-call deadline. *)
  run (fun ~sw env ->
      let clock = advancing_clock (Eio_mock.Clock.make ()) in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Lose_reply; Retry_server.Reply 401 ]
      in
      (match
         call client ~sw env server ~clock ~deadline:(Ox.Duration.ms 50)
           ~replay_policy:T.Allow_duplicate_effects ()
       with
      | Error `Timeout -> ()
      | _ -> Alcotest.fail "whole deadline must preserve Timeout");
      Alcotest.(check int) "^safe-s51t no retry beyond deadline" 1 !(server.requests))

let attempt_ceiling client () =
  (* ^safe-s51t: consent retains the transport's two-attempt default ceiling. *)
  run (fun ~sw env ->
      let clock = advancing_clock (Eio_mock.Clock.make ()) in
      let server =
        Retry_server.start ~sw ~net:env#net
          [ Retry_server.Lose_reply; Retry_server.Truncate_reply; Retry_server.Reply 401 ]
      in
      (match
         call client ~sw env server ~clock ~replay_policy:T.Allow_duplicate_effects ()
       with
      | Error (`Unavailable { status = Some 200; message; _ }) ->
          Alcotest.(check string)
            "^safe-3o27 final failure, not first" "response body truncated" message
      | _ -> Alcotest.fail "final truncated response must propagate");
      Alcotest.(check int) "^safe-s51t only two attempts" 2 !(server.requests))

let cancellation client () =
  (* ^safe-3o27: consent neither masks caller cancellation nor undoes commit. *)
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
                  match call client ~sw env server ~clock:env#clock ?replay_policy () with
                  | _ -> Alcotest.fail "cancellation became a result"
                  | exception Eio.Cancel.Cancelled Exit -> propagated := true));
          Alcotest.(check bool) "^safe-3o27 original cancellation reason" true !propagated;
          Eio.Promise.await server.closed;
          Alcotest.(check int) "^safe-o2b6 no replay on cancellation" 1 !(server.requests);
          Alcotest.(check int) "^safe-3o27 remote commit remains" 1 !(server.effects)))
    [ None; Some T.Allow_duplicate_effects ]

let () =
  Alcotest.run "public client replay consent"
    (List.map
       (fun (name, client) ->
         ( name,
           List.map
             (fun (label, test) -> Alcotest.test_case label `Quick (test client))
             [
               ("^safe-o2b6 default refuses replay", default_once);
               ("^safe-o2b6 duplicate consent", consent_duplicates);
               ("^safe-3o27 before commit", before_commit);
               ("^safe-3o27 attempt timeout", attempt_timeout);
               ("^safe-s51t deadline", deadline_stops_replay);
               ("^safe-s51t ceiling and final error", attempt_ceiling);
               ("^safe-3o27 cancellation", cancellation);
             ] ))
       [ ("SystemOne", Systemone); ("chat", Chat) ])
