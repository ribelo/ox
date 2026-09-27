(* ^nso-zmfp: at most two attempts, the second only after a transport failure, a timeout
   of the first attempt, or HTTP 429/529, with a short backoff on the clock, all inside
   the caller's deadline. ^nso-61ka: each evaluation's usage and cost are logged at debug
   with the request id.

   The backoff is 100 ms on the real clock, so a case that expects a second attempt costs
   that much wall time (^nso-hcfr). *)

open Test_helpers

let unavailable body status = Fake_server.ok ~status ~reason:"Status" body

let test_429_retries () =
  (* ^nso-zmfp: 429 is the retryable status; the second answer is taken. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"slow down"}|} 429 @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let response =
        expect_ok
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "two attempts" 2 (Fake_server.connections server);
      Alcotest.(check string)
        "the second reply is the answer" model response.Eta_ai_systemone.Codecs.model)

let test_529_retries () =
  (* ^nso-zmfp: 529 is the other retryable status. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"overloaded"}|} 529 @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      ignore
        (expect_ok
           (Eta_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      Alcotest.(check int) "two attempts" 2 (Fake_server.connections server))

let test_429_exhausted () =
  (* ^nso-zmfp: two 429s are two attempts, and the failure is retryable for the caller. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"slow down"}|} 429
          @ unavailable {|{"error":"slow down"}|} 429)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "exactly two attempts" 2 (Fake_server.connections server);
      Alcotest.(check bool) "^nso-77t7 retryable" true (Eta_ai.Error.retryable error))

let test_401_no_retry () =
  (* ^nso-zmfp: authentication is not a transport failure. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"bad key"}|} 401)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "authentication" true
        (contains (Eta_ai.Error.to_string error) "authentication failed"))

let test_500_no_retry () =
  (* ^nso-zmfp: a 5xx that is neither 429 nor 529 is answered once. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"broken"}|} 500)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "unavailable" true
        (contains (Eta_ai.Error.to_string error) "unavailable"))

let test_400_no_retry () =
  (* ^nso-zmfp: a 4xx that is neither 429 nor 529 is answered once. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"bad request"}|} 400)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "invalid response" true
        (contains (Eta_ai.Error.to_string error) "invalid response"))

let test_transport_failure_retries () =
  (* ^nso-zmfp: the first attempt fails on the wire, so the second is tried. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.after Eta.Duration.zero Fake_server.Silent
          @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let response =
        expect_ok
          (Eta_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "two attempts" 2 (Fake_server.connections server);
      Alcotest.(check string)
        "the second reply is the answer" model response.Eta_ai_systemone.Codecs.model)

let test_attempt_timeout_is_retryable () =
  (* ^nso-zmfp: both attempts time out inside the deadline; the failure is Timeout. The
     attempt cap is short, so each attempt gives up long before the peer answers. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.after (Eta.Duration.ms 60) Fake_server.Silent
          @ Fake_server.after (Eta.Duration.ms 60) Fake_server.Silent)
      in
      let client = client ~sw env server ~timeout:attempt_timeout () in
      (match
         Eta_ai_systemone.Client.evaluate client ~deadline ~state
           ~questions:choice_questions
       with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Eta_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "a stalled attempt returned an answer");
      Alcotest.(check int) "two attempts" 2 (Fake_server.connections server))

let test_usage_logged () =
  (* ^nso-61ka: usage and cost reach the debug log with the request id. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      ignore
        (expect_ok
           (Eta_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      let records =
        Eta_observability.Logger.Memory.find ~level:Eta_observability.Logger.Debug memory
      in
      let record =
        match
          List.find_opt
            (fun record -> String.equal record.Eta_observability.Logger.msg "systemone")
            records
        with
        | Some record -> record
        | None -> Alcotest.fail "no systemone usage record"
      in
      let field name =
        match List.assoc_opt name record.Eta_observability.Logger.fields with
        | Some (Eta_observability.Logger.Int value) -> string_of_int value
        | Some (Eta_observability.Logger.Float value) -> Printf.sprintf "%g" value
        | Some (Eta_observability.Logger.String value) -> value
        | Some _ -> Alcotest.failf "field %s has an unexpected shape" name
        | None -> Alcotest.failf "no field %s" name
      in
      Alcotest.(check string) "input tokens" "10" (field "input_tokens");
      Alcotest.(check string) "output tokens" "2" (field "output_tokens");
      Alcotest.(check string) "cost" "0.0001" (field "cost");
      Alcotest.(check string) "request id" "gen-1" (field "request_id");
      Alcotest.(check string) "model" model (field "model"))

let test_key_never_logged () =
  (* The key travels as a redacted value; a debug log cannot show it. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      ignore
        (expect_ok
           (Eta_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      let lines =
        Eta_observability.Logger.Memory.records memory
        |> List.map Eta_observability.Logger.to_string
      in
      Alcotest.(check bool)
        "the key is not in the log" false
        (List.exists
           (fun line -> contains line (Eta_observability.Redact.expose key))
           lines))

let () =
  Alcotest.run "AI System One retry"
    [
      ( "retry matrix",
        [
          Alcotest.test_case "^nso-zmfp 429 then success" `Quick test_429_retries;
          Alcotest.test_case "^nso-zmfp 529 then success" `Quick test_529_retries;
          Alcotest.test_case "^nso-zmfp 429 twice" `Quick test_429_exhausted;
          Alcotest.test_case "^nso-zmfp 401 is not retried" `Quick test_401_no_retry;
          Alcotest.test_case "^nso-zmfp 500 is not retried" `Quick test_500_no_retry;
          Alcotest.test_case "^nso-zmfp 400 is not retried" `Quick test_400_no_retry;
          Alcotest.test_case "^nso-zmfp transport failure retries" `Quick
            test_transport_failure_retries;
          Alcotest.test_case "^nso-zmfp attempt timeout is retryable" `Quick
            test_attempt_timeout_is_retryable;
        ] );
      ( "observability",
        [
          Alcotest.test_case "^nso-61ka usage logged at debug" `Quick test_usage_logged;
          Alcotest.test_case "^nso-77t7 the key is never logged" `Quick
            test_key_never_logged;
        ] );
    ]
