(* The one live chat smoke (^nchat-kk3g): opt-in, off by default, and the only chat test
   that talks to a real endpoint.

   It runs only when [ETA_AI_LIVE_SMOKE=1]; it reads the key from [OPENROUTER_API_KEY] and
   never prints, logs or encodes it — the key travels as {!Eta_observability.Redact.t} and
   the only revealing path is the Authorization header of the request.
   [ETA_AI_LIVE_CHAT_MODEL] overrides the model (default: the text helper's
   [inception/mercury-2.5]) and [ETA_AI_LIVE_CHAT_ENDPOINT] the endpoint (default:
   OpenRouter's chat route), so a DeepSeek or local endpoint can be smoked the same way.

   The call is the helper's own: a system instruction and one user message, JSON object
   required, reasoning off, bounded tokens. The reply's content must be a JSON object and
   the usage must be reported; nothing here asserts what the model said. *)

let model =
  match Sys.getenv_opt "ETA_AI_LIVE_CHAT_MODEL" with
  | Some model -> model
  | None -> Chat_helpers.chat_model

let endpoint =
  match Sys.getenv_opt "ETA_AI_LIVE_CHAT_ENDPOINT" with
  | Some endpoint -> endpoint
  | None -> Eta_ai_chat.Chat.default_endpoint

let smoke () =
  match Sys.getenv_opt "ETA_AI_LIVE_SMOKE" with
  | Some "1" -> (
      match Sys.getenv_opt "OPENROUTER_API_KEY" with
      | Some key when not (String.equal (String.trim key) "") ->
          Chat_helpers.run (fun ~sw env ->
              let http = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
              let logger, _ = Chat_helpers.memory_logger env in
              let client =
                Eta_ai_chat.Chat.create ~http ~clock:env#clock ~logger ~endpoint
                  ~api_key:(Eta_observability.Redact.make key) ()
              in
              let messages =
                [
                  Chat_helpers.system;
                  Chat_helpers.user
                    {|Return the JSON object {"text": "ada"}.|};
                ]
              in
              match
                Eta_ai_chat.Chat.complete client ~deadline:(Eta.Duration.seconds 60)
                  ~model ~messages ~max_tokens:64 ~json_object:true ~reasoning:`Disabled
                  ()
              with
              | Ok completion -> (
                  let content = completion.Eta_ai_chat.Codecs.content in
                  let is_object =
                    match Eta_json.parse content with
                    | Ok (`Assoc _) -> true
                    | Ok _ -> false
                    | Error error ->
                        Alcotest.failf "the completion is not JSON: %s"
                          (Format.asprintf "%a" Eta_json.pp_parse_error error)
                  in
                  Alcotest.(check bool) "the completion is a JSON object" true is_object;
                  Alcotest.(check bool)
                    "usage reported" true
                    (completion.Eta_ai_chat.Codecs.usage.total_tokens > 0))
              | Error error ->
                  Alcotest.failf "live chat smoke failed: %s"
                    (Eta_ai.Error.to_string error))
      | _ -> Alcotest.fail "ETA_AI_LIVE_SMOKE=1 needs OPENROUTER_API_KEY in the environment")
  | _ -> ()
