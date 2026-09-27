(* The one live smoke (^nso-hcfr): opt-in, off by default, and the only test that talks
   to a real endpoint.

   It runs only when [ETA_AI_LIVE_SMOKE=1]; it reads the key from [OPENROUTER_API_KEY] and
   never prints, logs or encodes it — the key travels as {!Eta_observability.Redact.t} and
   the only revealing path is the Authorization header of the request. [ETA_AI_LIVE_MODEL]
   overrides the model (default: the reference's [typesafe/jev-1.13-20260917]) and
   [ETA_AI_LIVE_ENDPOINT] the endpoint (default: OpenRouter's), so the same smoke covers
   `https://api.typesafe.ai/v1/systemone` with a TypeSafe key.

   The question is the smallest real one: one choice question whose criteria are the three
   operations jev-ultrafast always offers (`reference/model.py`). *)

let model =
  match Sys.getenv_opt "ETA_AI_LIVE_MODEL" with
  | Some model -> model
  | None -> Test_helpers.model

let endpoint =
  match Sys.getenv_opt "ETA_AI_LIVE_ENDPOINT" with
  | Some endpoint -> endpoint
  | None -> Eta_ai_systemone.Client.default_endpoint

let smoke () =
  match Sys.getenv_opt "ETA_AI_LIVE_SMOKE" with
  | Some "1" -> (
      match Sys.getenv_opt "OPENROUTER_API_KEY" with
      | Some key when not (String.equal (String.trim key) "") ->
          Test_helpers.run (fun ~sw env ->
              let http = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
              let logger, _ = Test_helpers.memory_logger env in
              let client =
                Eta_ai_systemone.Client.create ~http ~clock:env#clock ~logger ~endpoint
                  ~api_key:(Eta_observability.Redact.make key)
                  ~model ()
              in
              let state =
                `Assoc
                  [
                    ( "page",
                      `Assoc
                        [
                          ("url", `String "https://example.test/");
                          ("title", `String "Example");
                          ("text", `String "A page with one button.");
                        ] );
                    ("elements", `List []);
                    ("recent_actions", `List []);
                  ]
              in
              let questions =
                [
                  ( "operation",
                    Eta_ai_systemone.Codecs.choice
                      ~instructions:
                        (`Assoc
                           [
                             ("goal", `String "Click the button on the page");
                             ( "rules",
                               `String "Answer with the operation that advances the goal."
                             );
                           ])
                      ~criteria:
                        [
                          ("CLICK", `String "Click an element or button.");
                          ("DONE", `String "Every requirement is visibly satisfied.");
                          ("BLOCKED", `String "No supported operation can progress.");
                        ] );
                ]
              in
              match
                Eta_ai_systemone.Client.evaluate client
                  ~deadline:(Eta.Duration.seconds 60) ~state ~questions
              with
              | Ok response ->
                  Alcotest.(check string)
                    "the reply names the configured model" model
                    response.Eta_ai_systemone.Codecs.model;
                  Alcotest.(check bool)
                    "the reply answers the operation" true
                    (Option.is_some (Eta_ai_systemone.Client.answer "operation" response))
              | Error error ->
                  Alcotest.failf "live smoke failed: %s" (Eta_ai.Error.to_string error))
      | _ ->
          Alcotest.fail "ETA_AI_LIVE_SMOKE=1 needs OPENROUTER_API_KEY in the environment")
  | _ -> ()
