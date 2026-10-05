(* ^safe-o2b6 ^safe-a5mq ^safe-3o27: System One inherits the safe POST default.
   Errors retain the ^nso-zmfp classifications but never authorize automatic replay.
   Explicit duplicate-effect consent is tested at Transport.post_json in safety_retry.
   ^nso-61ka: each evaluation's usage and cost are logged with the request id. *)

open Test_helpers

let unavailable body status = Fake_server.ok ~status ~reason:"Status" body

let test_429_no_replay () =
  (* ^safe-a5mq: 429 remains retryable in the error, not replay permission. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"slow down"}|} 429 @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "^safe-o2b6 one attempt" 1 (Fake_server.connections server);
      match error with
      | `Unavailable { retryable = true; _ } -> ()
      | _ -> Alcotest.fail "^safe-a5mq expected unchanged Unavailable classification")

let test_529_no_replay () =
  (* ^safe-a5mq: 529 supplies no non-commit evidence. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"overloaded"}|} 529 @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "^safe-o2b6 one attempt" 1 (Fake_server.connections server);
      match error with
      | `Unavailable { status = Some 529; retryable = true; _ } -> ()
      | _ -> Alcotest.fail "^safe-a5mq expected unchanged 529 classification")

let test_429_classification () =
  (* ^safe-a5mq: the error classification does not authorize a second POST. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (unavailable {|{"error":"slow down"}|} 429
          @ unavailable {|{"error":"slow down"}|} 429)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int)
        "^safe-a5mq no retry despite status" 1
        (Fake_server.connections server);
      Alcotest.(check bool) "^nso-77t7 retryable" true (Ox_ai.Error.retryable error))

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
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "authentication" true
        (contains (Ox_ai.Error.to_string error) "authentication failed"))

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
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "unavailable" true
        (contains (Ox_ai.Error.to_string error) "unavailable"))

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
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one attempt" 1 (Fake_server.connections server);
      Alcotest.(check bool)
        "invalid response" true
        (contains (Ox_ai.Error.to_string error) "invalid response"))

let test_transport_failure_no_replay () =
  (* ^safe-o2b6: ambiguous transport failure is not automatically repeated. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.after Ox.Duration.zero Fake_server.Silent
          @ Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "^safe-o2b6 one attempt" 1 (Fake_server.connections server);
      match error with
      | `Unavailable { retryable = true; _ } -> ()
      | _ -> Alcotest.fail "^safe-a5mq expected unchanged Unavailable classification")

let test_attempt_timeout_no_replay () =
  (* ^safe-3o27: one attempt times out inside the deadline; no replay follows. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.after (Ox.Duration.ms 60) Fake_server.Silent
          @ Fake_server.after (Ox.Duration.ms 60) Fake_server.Silent)
      in
      let client = client ~sw env server ~timeout:attempt_timeout () in
      (match
         Ox_ai_systemone.Client.evaluate client ~deadline ~state
           ~questions:choice_questions
       with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Ox_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "a stalled attempt returned an answer");
      Alcotest.(check int)
        "^safe-3o27 no retry after timeout" 1
        (Fake_server.connections server))

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
           (Ox_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      let records =
        Ox_observability.Logger.Memory.find ~level:Ox_observability.Logger.Debug memory
      in
      let record =
        match
          List.find_opt
            (fun record -> String.equal record.Ox_observability.Logger.msg "systemone")
            records
        with
        | Some record -> record
        | None -> Alcotest.fail "no systemone usage record"
      in
      let field name =
        match List.assoc_opt name record.Ox_observability.Logger.fields with
        | Some (Ox_observability.Logger.Int value) -> string_of_int value
        | Some (Ox_observability.Logger.Float value) -> Printf.sprintf "%g" value
        | Some (Ox_observability.Logger.String value) -> value
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
           (Ox_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      let lines =
        Ox_observability.Logger.Memory.records memory
        |> List.map Ox_observability.Logger.to_string
      in
      Alcotest.(check bool)
        "the key is not in the log" false
        (List.exists
           (fun line -> contains line (Ox_observability.Redact.expose key))
           lines))

let () =
  Alcotest.run "AI System One retry"
    [
      ( "retry matrix",
        [
          Alcotest.test_case "^safe-a5mq 429 does not authorize replay" `Quick
            test_429_no_replay;
          Alcotest.test_case "^safe-a5mq 529 does not authorize replay" `Quick
            test_529_no_replay;
          Alcotest.test_case "^safe-a5mq 429 classification unchanged" `Quick
            test_429_classification;
          Alcotest.test_case "^nso-zmfp 401 is not retried" `Quick test_401_no_retry;
          Alcotest.test_case "^nso-zmfp 500 is not retried" `Quick test_500_no_retry;
          Alcotest.test_case "^nso-zmfp 400 is not retried" `Quick test_400_no_retry;
          Alcotest.test_case "^safe-o2b6 transport failure does not replay" `Quick
            test_transport_failure_no_replay;
          Alcotest.test_case "^safe-3o27 attempt timeout does not replay" `Quick
            test_attempt_timeout_no_replay;
        ] );
      ( "observability",
        [
          Alcotest.test_case "^nso-61ka usage logged at debug" `Quick test_usage_logged;
          Alcotest.test_case "^nso-77t7 the key is never logged" `Quick
            test_key_never_logged;
        ] );
    ]
