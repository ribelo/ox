(* ^nso-pflg: both bounds hold. The request bound is checked before a socket exists; the
   response bound is enforced while reading, by {!Ox_http.Client}. ^nso-zmfp: a body too
   large to read is the one refusal that repeats. *)

open Test_helpers

let test_request_bound () =
  (* ^nso-pflg: over 4 MiB is refused before sending. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let state =
        `Assoc
          [ ("page", `Assoc [ ("text", `String (String.make (4 * 1024 * 1024) 'x')) ]) ]
      in
      match
        Ox_ai_systemone.Client.evaluate client ~deadline ~state
          ~questions:choice_questions
      with
      | Ok _ -> Alcotest.fail "an oversized request was sent"
      | Error (`Input_too_large { limit; length }) ->
          Alcotest.(check int) "the bound is 4 MiB" (4 * 1024 * 1024) limit;
          Alcotest.(check bool) "the length is over it" true (length > limit);
          Alcotest.(check int) "nothing was sent" 0 (Fake_server.connections server)
      | Error error ->
          Alcotest.failf "not Input_too_large: %s" (Ox_ai.Error.to_string error))

let test_request_under_bound () =
  (* The bound is a ceiling, not a target: a large request still goes. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let state =
        `Assoc
          [ ("page", `Assoc [ ("text", `String (String.make (3 * 1024 * 1024) 'x')) ]) ]
      in
      ignore
        (expect_ok
           (Ox_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      Alcotest.(check int) "sent once" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "the body arrived" true
        (String.length (Fake_server.body server) > 3 * 1024 * 1024))

let test_configured_request_bound () =
  (* ^nso-pflg: the bound is the client's, so a caller can set it below the default. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let http = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
      let logger, _ = memory_logger env in
      let client =
        Ox_ai_systemone.Client.create ~http ~clock:env#clock ~logger
          ~endpoint:(Fake_server.url server "/v1/systemone")
          ~api_key:key ~model ~max_request_bytes:64 ()
      in
      match
        Ox_ai_systemone.Client.evaluate client ~deadline ~state
          ~questions:choice_questions
      with
      | Error (`Input_too_large { limit; _ }) ->
          Alcotest.(check int) "the configured bound" 64 limit;
          Alcotest.(check int) "nothing was sent" 0 (Fake_server.connections server)
      | Ok _ -> Alcotest.fail "an oversized request was sent"
      | Error error ->
          Alcotest.failf "not Input_too_large: %s" (Ox_ai.Error.to_string error))

let test_response_bound () =
  (* ^nso-pflg: over 1 MiB is rejected after one attempt — the reference adapter's
     INVALID_RESPONSE is not retryable (^nso-zmfp). *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.ok (String.make ((1024 * 1024) + 1) 'x'))
      in
      let client = client ~sw env server () in
      match
        Ox_ai_systemone.Client.evaluate client ~deadline ~state
          ~questions:choice_questions
      with
      | Ok _ -> Alcotest.fail "an oversized response was accepted"
      | Error error ->
          let text = Ox_ai.Error.to_string error in
          Alcotest.(check bool)
            ("^nso-pflg refused: " ^ text)
            true
            (contains text "invalid response");
          Alcotest.(check int)
            ("^nso-zmfp one attempt: " ^ text)
            1
            (Fake_server.connections server))

let test_expired_deadline () =
  (* A deadline already passed sends nothing. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      match
        Ox_ai_systemone.Client.evaluate client ~deadline:Ox.Duration.zero ~state
          ~questions:choice_questions
      with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Ox_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "an expired deadline was ignored")

let () =
  Alcotest.run "AI System One bounds"
    [
      ( "bounds",
        [
          Alcotest.test_case "^nso-pflg request over 4 MiB" `Quick test_request_bound;
          Alcotest.test_case "^nso-pflg request under the bound" `Quick
            test_request_under_bound;
          Alcotest.test_case "^nso-pflg configured request bound" `Quick
            test_configured_request_bound;
          Alcotest.test_case "^nso-pflg response over 1 MiB" `Quick test_response_bound;
          Alcotest.test_case "^nso-zmfp expired deadline" `Quick test_expired_deadline;
        ] );
    ]
