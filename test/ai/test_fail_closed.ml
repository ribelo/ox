(* ^nso-megl ^nso-ttfj: the reply is decoded fail-closed. Every case is the reference
   reply with one thing broken; the client must refuse it and name the offending value,
   never default. ^nso-hcfr: the fake server scripts each one. *)

open Test_helpers

let refusal body =
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok body)
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check bool) "^nso-megl refused" false (Ox_ai.Error.retryable error);
      (error, Fake_server.connections server))

let expect_message needle (error, _) =
  Alcotest.(check bool)
    ("error names " ^ needle) true
    (contains (Ox_ai.Error.to_string error) needle)

(* A body too large to read is the reference adapter's INVALID_RESPONSE: not retryable,
   so it ends the call after one attempt (`reference/jev.ts`, its bound read and its
   retry loop). *)
let test_oversized_body_refused () =
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.ok (String.make ((1024 * 1024) + 1) 'x')
          @ Fake_server.ok (String.make ((1024 * 1024) + 1) 'x'))
      in
      let client = client ~sw env server () in
      let error =
        expect_error
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int)
        "^nso-zmfp exactly one attempt" 1
        (Fake_server.connections server);
      Alcotest.(check bool)
        "^nso-pflg refused" true
        (contains (Ox_ai.Error.to_string error) "invalid response");
      Alcotest.(check bool) "^nso-77t7 not retryable" false (Ox_ai.Error.retryable error))

let test_missing_model () =
  (* ^nso-megl: a required top-level field is required. *)
  expect_message "response: missing field model"
    (refusal
       {|{"answers":{"operation":{"type":"choice","choice":"CLICK","probabilities":{"CLICK":1},"confidence":1}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|})

let test_missing_usage () =
  expect_message "usage"
    (refusal {|{"model":"typesafe/jev-1.13-20260917","answers":{},"usage":{}}|})

let test_missing_answer_field () =
  expect_message "confidence"
    (refusal
       {|{"model":"typesafe/jev-1.13-20260917","answers":{"operation":{"type":"choice","choice":"CLICK","probabilities":{"CLICK":1}}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|})

let test_wrong_type () =
  expect_message "probabilities"
    (refusal
       {|{"model":"typesafe/jev-1.13-20260917","answers":{"operation":{"type":"choice","choice":"CLICK","probabilities":[1,2],"confidence":1}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|})

let test_unknown_answer_type () =
  expect_message "unknown answer type"
    (refusal
       {|{"model":"typesafe/jev-1.13-20260917","answers":{"operation":{"type":"ranking","choice":"CLICK","probabilities":{"CLICK":1},"confidence":1}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|})

let test_named_answer () =
  (* The failing answer's name is in the message, so a caller knows which question. *)
  expect_message "operation"
    (refusal
       {|{"model":"typesafe/jev-1.13-20260917","answers":{"operation":{"type":"choice","choice":3,"probabilities":{"CLICK":1},"confidence":1}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|})

let test_malformed_json () =
  expect_message "malformed JSON"
    (refusal {|{"model":"typesafe/jev-1.13-20260917","answers":|})

let test_wrong_model () =
  (* ^nso-ttfj: a provider substitution is caught, and it is not retried. *)
  let error, connections =
    refusal
      {|{"model":"typesafe/jev-1.13-20260917-other","answers":{"operation":{"type":"choice","choice":"CLICK","probabilities":{"CLICK":1},"confidence":1}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|}
  in
  Alcotest.(check int) "one attempt" 1 connections;
  match error with
  | `Model_mismatch { expected; got } ->
      Alcotest.(check string) "expected" model expected;
      Alcotest.(check string) "got" "typesafe/jev-1.13-20260917-other" got
  | error -> Alcotest.failf "not a model mismatch: %s" (Ox_ai.Error.to_string error)

let test_statuses () =
  (* ^nso-77t7: the statuses the reference names map to the reference's codes. *)
  let cases =
    [
      (401, "authentication failed", "invalid response");
      (400, "invalid response", "authentication failed");
      (404, "invalid response", "authentication failed");
      (500, "unavailable", "invalid response");
    ]
  in
  List.iter
    (fun (status, expected, unexpected) ->
      run (fun ~sw env ->
          let server =
            Fake_server.serve ~net:env#net ~clock:env#clock ~sw
              (Fake_server.ok ~status ~reason:"Status" {|{"error":"no"}|})
          in
          let client = client ~sw env server () in
          let error =
            expect_error
              (Ox_ai_systemone.Client.evaluate client ~deadline ~state
                 ~questions:choice_questions)
          in
          let text = Ox_ai.Error.to_string error in
          Alcotest.(check bool)
            (Printf.sprintf "%d says %s" status expected)
            true (contains text expected);
          Alcotest.(check bool)
            (Printf.sprintf "%d does not say %s" status unexpected)
            false (contains text unexpected)))
    cases

let test_choice_valid () =
  (* ^nso-megl: the reference's own answer check, available to the caller. *)
  let answer probabilities confidence choice =
    { Ox_ai_systemone.Types.choice; probabilities; confidence }
  in
  Alcotest.(check bool)
    "a good distribution" true
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.9); ("DONE", 0.1) ] 0.8 "CLICK"));
  Alcotest.(check bool)
    "a tie is allowed" true
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.5); ("DONE", 0.5) ] 0.8 "DONE"));
  Alcotest.(check bool)
    "confidence over 1" false
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.9); ("DONE", 0.1) ] 1.5 "CLICK"));
  Alcotest.(check bool)
    "not a distribution" false
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.9); ("DONE", 0.5) ] 0.8 "CLICK"));
  Alcotest.(check bool)
    "the choice is not the most probable" false
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.1); ("DONE", 0.9) ] 0.8 "CLICK"));
  Alcotest.(check bool)
    "the choice is not offered" false
    (Ox_ai_systemone.Codecs.choice_answer_valid
       (answer [ ("CLICK", 0.9); ("DONE", 0.1) ] 0.8 "BLOCKED"))

let test_score_answer () =
  (* A score answer keeps its legend keyed by the level index the API uses. *)
  run (fun ~sw env ->
      let body =
        {|{"model":"typesafe/jev-1.13-20260917","answers":{"how_wrong":{"type":"score","score":2,"legend":{"1":"none","2":"a few","3":"many"},"probabilities":{"1":0.1,"2":0.7,"3":0.2},"confidence":0.6}},"usage":{"input_tokens":1,"output_tokens":1,"cost":0}}|}
      in
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok body)
      in
      let client = client ~sw env server () in
      let response =
        expect_ok (Ox_ai_systemone.Client.evaluate client ~deadline ~state ~questions:[])
      in
      match Ox_ai_systemone.Client.answer "how_wrong" response with
      | Some (Ox_ai_systemone.Codecs.Score answer) ->
          Alcotest.(check (float 1e-12)) "score" 2. answer.Ox_ai_systemone.Types.score;
          Alcotest.(check (option string))
            "level" (Some "a few")
            (Ox_ai_systemone.Codecs.level "2" answer);
          Alcotest.(check (option string))
            "absent level" None
            (Ox_ai_systemone.Codecs.level "9" answer)
      | Some (Ox_ai_systemone.Codecs.Choice _) ->
          Alcotest.fail "a choice answer for a score question"
      | None -> Alcotest.fail "the reply did not name the score answer")

let () =
  Alcotest.run "AI System One fail-closed"
    [
      ( "decoding",
        [
          Alcotest.test_case "^nso-megl missing model" `Quick test_missing_model;
          Alcotest.test_case "^nso-megl missing usage" `Quick test_missing_usage;
          Alcotest.test_case "^nso-megl missing answer field" `Quick
            test_missing_answer_field;
          Alcotest.test_case "^nso-megl wrong member type" `Quick test_wrong_type;
          Alcotest.test_case "^nso-megl unknown answer discriminant" `Quick
            test_unknown_answer_type;
          Alcotest.test_case "^nso-megl the failing answer is named" `Quick
            test_named_answer;
          Alcotest.test_case "^nso-megl malformed JSON" `Quick test_malformed_json;
          Alcotest.test_case "^nso-ttfj model mismatch" `Quick test_wrong_model;
          Alcotest.test_case "^nso-77t7 status mapping" `Quick test_statuses;
          Alcotest.test_case "^nso-pflg oversized body is refused once" `Quick
            test_oversized_body_refused;
          Alcotest.test_case "^nso-megl choice answer check" `Quick test_choice_valid;
          Alcotest.test_case "score answer and legend" `Quick test_score_answer;
        ] );
    ]
