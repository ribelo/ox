(* Story tests for the System One client against the fake server (^nso-hcfr).

   ^nso-5hom: one call decides. ^nso-jz8v: choice and score questions are encoded exactly
   as the contract expects. ^nso-megl: the reply is decoded fail-closed. ^nso-ttfj: the
   reply's model is checked. ^nso-pflg: both bounds hold. ^nso-zmfp: the retry matrix.
   Every case names the reference: `reference/jev.ts` and `reference/model.py`. *)

open Test_helpers

let test_evaluate () =
  (* ^nso-5hom: Ox_ai_systemone.create + evaluate is one call for one decision. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let response =
        expect_ok
          (Ox_ai_systemone.Client.evaluate client ~deadline ~state
             ~questions:choice_questions)
      in
      Alcotest.(check int) "one connection" 1 (Fake_server.connections server);
      let method_, headers, _ = Option.get (Fake_server.request server) in
      Alcotest.(check string) "method" "POST" method_;
      Alcotest.(check (option string))
        "path" (Some "/v1/systemone")
        (List.assoc_opt "host" headers);
      Alcotest.(check (option string))
        "bearer header"
        (Some ("Bearer " ^ Ox_observability.Redact.expose key))
        (List.assoc_opt "authorization" headers);
      Alcotest.(check (option string))
        "content type" (Some "application/json")
        (List.assoc_opt "content-type" headers);
      Alcotest.(check string) "model" model response.Ox_ai_systemone.Codecs.model;
      Alcotest.(check int)
        "input tokens" 10 response.Ox_ai_systemone.Codecs.usage.input_tokens;
      Alcotest.(check int)
        "output tokens" 2 response.Ox_ai_systemone.Codecs.usage.output_tokens;
      Alcotest.(check (float 1e-12))
        "cost" 0.0001 response.Ox_ai_systemone.Codecs.usage.cost;
      Alcotest.(check (option string))
        "request id" (Some "gen-1") response.Ox_ai_systemone.Codecs.id;
      let answer =
        match Ox_ai_systemone.Client.answer "operation" response with
        | Some (Ox_ai_systemone.Codecs.Choice answer) -> answer
        | Some (Ox_ai_systemone.Codecs.Score _) ->
            Alcotest.fail "a score answer for a choice question"
        | None -> Alcotest.fail "the reply did not name the operation answer"
      in
      Alcotest.(check string) "choice" "CLICK" answer.Ox_ai_systemone.Types.choice;
      Alcotest.(check (option (float 1e-12)))
        "chosen probability" (Some 0.9)
        (Ox_ai_systemone.Codecs.probability "CLICK" answer);
      Alcotest.(check (option (float 1e-12)))
        "other probability" (Some 0.1)
        (Ox_ai_systemone.Codecs.probability "DONE" answer);
      Alcotest.(check (option (float 1e-12)))
        "absent probability" None
        (Ox_ai_systemone.Codecs.probability "BLOCKED" answer))

let test_choice_question () =
  (* ^nso-jz8v: the choice question is what model.py builds: instructions as raw JSON and
     criteria keyed by option with the value or null. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      ignore
        (expect_ok
           (Ox_ai_systemone.Client.evaluate client ~deadline ~state
              ~questions:choice_questions));
      let body = jbody server in
      Alcotest.(check string) "model" model (text_of (member "model" body));
      Alcotest.(check string)
        "state" "https://example.test/"
        (text_of (member "url" (member "page" (member "state" body))));
      let questions = member "questions" body in
      let operation = member "operation" questions in
      Alcotest.(check string)
        "question discriminant" "choice"
        (text_of (member "type" operation));
      Alcotest.(check string)
        "instructions" "buy a ticket"
        (text_of (member "goal" (member "instructions" operation)));
      let criteria = member "criteria" operation in
      Alcotest.(check string)
        "criterion value" "Click"
        (text_of (member "CLICK" criteria));
      Alcotest.(check bool)
        "null criterion" true
        (match member "DONE" criteria with `Null -> true | _ -> false);
      Alcotest.(check string)
        "request is compact JSON" (Fake_server.body server) (Yojson.Safe.to_string body))

let test_score_question () =
  (* ^nso-jz8v: a score question keeps its levels in order. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client = client ~sw env server () in
      let questions =
        [
          ( "how_wrong",
            Ox_ai_systemone.Codecs.score
              ~instructions:
                (Ox_json.object_ [ ("goal", Some (Ox_json.string "count errors")) ])
              ~criteria:[ "none"; "a few"; "many" ] );
        ]
      in
      ignore
        (expect_ok (Ox_ai_systemone.Client.evaluate client ~deadline ~state ~questions));
      let body = jbody server in
      let question = member "how_wrong" (member "questions" body) in
      Alcotest.(check string)
        "question discriminant" "score"
        (text_of (member "type" question));
      Alcotest.(check (list string))
        "levels in order" [ "none"; "a few"; "many" ]
        (List.map text_of (list_of (member "criteria" question)));
      Alcotest.(check string)
        "instructions" "count errors"
        (text_of (member "goal" (member "instructions" question))))

let test_question_names () =
  let choice =
    Ox_ai_systemone.Codecs.choice ~instructions:`Null ~criteria:[ ("a", `Null) ]
  and score = Ox_ai_systemone.Codecs.score ~instructions:`Null ~criteria:[ "a" ] in
  Alcotest.(check string) "choice" "choice" (Ox_ai_systemone.Codecs.question_name choice);
  Alcotest.(check string) "score" "score" (Ox_ai_systemone.Codecs.question_name score)

let test_endpoints () =
  (* ^nso-5hom: both endpoints serve the same contract and are named constants. *)
  Alcotest.(check string)
    "openrouter default" "https://openrouter.ai/api/v1/systemone"
    Ox_ai_systemone.Client.default_endpoint;
  Alcotest.(check string)
    "typesafe" "https://api.typesafe.ai/v1/systemone"
    Ox_ai_systemone.Client.typesafe_endpoint

let test_configurable_endpoint () =
  (* The endpoint is configuration, not a constant, so a local server and the other
     production endpoint both work. *)
  run (fun ~sw env ->
      let server =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok response_body)
      in
      let client =
        client ~sw env server ~endpoint:(Fake_server.url server "/custom/path") ()
      in
      ignore
        (expect_ok
           (Ox_ai_systemone.Client.evaluate client ~deadline ~state ~questions:[]));
      let _, headers, _ = Option.get (Fake_server.request server) in
      Alcotest.(check (option string))
        "custom path" (Some "/custom/path")
        (List.assoc_opt "host" headers))

let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.env >) in
  let model = Test_live.model ~caps () in
  let endpoint = Test_live.endpoint ~caps () in
  Alcotest.run "AI System One contract"
    [
      ( "contract",
        [
          Alcotest.test_case "^nso-5hom one call decides" `Quick test_evaluate;
          Alcotest.test_case "^nso-jz8v choice question encoding" `Quick
            test_choice_question;
          Alcotest.test_case "^nso-jz8v score question encoding" `Quick
            test_score_question;
          Alcotest.test_case "question discriminants" `Quick test_question_names;
          Alcotest.test_case "endpoint constants" `Quick test_endpoints;
          Alcotest.test_case "^nso-5hom configurable endpoint" `Quick
            test_configurable_endpoint;
        ] );
      ( "live",
        [
          Alcotest.test_case "^nso-hcfr live smoke (opt-in)" `Quick
            (Test_live.smoke ~caps ~model ~endpoint);
        ] );
    ]
