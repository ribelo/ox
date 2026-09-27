(* Story tests for the chat client against the fake chat server (^nchat-kk3g).

   ^nchat-dys0: one call returns the first choice's content and usage. ^nchat-6kd8: the
   reasoning control is written in the two forms OpenRouter documents and omitted when the
   caller says nothing. ^nchat-02vr: `~json_object:true` requires a JSON object.
   ^nchat-wtog: decoding, bounds, the two-attempt policy and the typed errors are the
   System One client's, because both share {!Eta_ai}. ^nchat-96zw: usage at debug. *)

open Chat_helpers
module Codecs = Eta_ai_chat.Codecs
module Types = Eta_ai_chat.Types

let expect_content expected completion =
  Alcotest.(check string) "content" expected completion.Codecs.content

let test_complete () =
  (* ^nchat-dys0: `Chat.complete` is one call for the text helper. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      let completion = expect_ok (complete client ~max_tokens:1024 ()) in
      expect_content {|{"text":"ada"}|} completion;
      Alcotest.(check string) "the model that answered" chat_model completion.model;
      Alcotest.(check (option string))
        "finish reason" (Some "stop") completion.finish_reason;
      Alcotest.(check int) "prompt tokens" 11 completion.usage.prompt_tokens;
      Alcotest.(check int) "completion tokens" 3 completion.usage.completion_tokens;
      Alcotest.(check int) "total tokens" 14 completion.usage.total_tokens;
      Alcotest.(check (option string)) "request id" (Some "gen-chat-1") completion.id;
      Alcotest.(check int) "one connection" 1 (Chat_server.connections server);
      let method_, headers, _ = Option.get (Chat_server.request server) in
      Alcotest.(check string) "method" "POST" method_;
      Alcotest.(check (option string))
        "path" (Some Chat_server.path)
        (List.assoc_opt "host" headers);
      Alcotest.(check (option string))
        "bearer header"
        (Some ("Bearer " ^ Eta_observability.Redact.expose chat_key))
        (List.assoc_opt "authorization" headers);
      Alcotest.(check (option string))
        "content type" (Some "application/json")
        (List.assoc_opt "content-type" headers);
      let body = jbody server in
      Alcotest.(check string) "model" chat_model (text_of (member "model" body));
      Alcotest.(check (option int))
        "max_tokens" (Some 1024)
        (match member "max_tokens" body with `Int tokens -> Some tokens | _ -> None);
      let sent = list_of (member "messages" body) in
      Alcotest.(check int) "two messages" 2 (List.length sent);
      Alcotest.(check string)
        "system role" "system"
        (text_of (member "role" (List.nth sent 0)));
      Alcotest.(check string)
        "system content" "Answer with one JSON object."
        (text_of (member "content" (List.nth sent 0)));
      Alcotest.(check string)
        "user role" "user"
        (text_of (member "role" (List.nth sent 1)));
      Alcotest.(check string)
        "user content" {|{"goal":"type ada"}|}
        (text_of (member "content" (List.nth sent 1)));
      Alcotest.(check string)
        "the request is compact JSON" (Chat_server.body server)
        (Yojson.Safe.to_string body))

let test_reasoning_disabled () =
  (* ^nchat-6kd8: the hot path turns reasoning off explicitly. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore (expect_ok (complete client ~reasoning:`Disabled ()));
      Alcotest.(check string)
        "reasoning enabled false" {|{"enabled":false}|}
        (Yojson.Safe.to_string (member "reasoning" (jbody server))))

let test_reasoning_effort () =
  (* ^nchat-6kd8: the effort form is OpenRouter's other member. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore (expect_ok (complete client ~reasoning:(`Effort "low") ()));
      Alcotest.(check string)
        "reasoning effort" {|{"effort":"low"}|}
        (Yojson.Safe.to_string (member "reasoning" (jbody server))))

let test_reasoning_omitted () =
  (* ^nchat-6kd8: a caller that says nothing sends no reasoning member at all. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore (expect_ok (complete client ()));
      Alcotest.(check bool)
        "no reasoning member" false
        (has_member "reasoning" (jbody server)))

let test_json_object () =
  (* ^nchat-02vr: the helper's output is required to be JSON. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore (expect_ok (complete client ~json_object:true ()));
      Alcotest.(check string)
        "response format" {|{"type":"json_object"}|}
        (Yojson.Safe.to_string (member "response_format" (jbody server))))

let test_json_object_omitted () =
  (* ^nchat-02vr: without the flag the member is absent, so a provider that does not
     support it is never asked. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore (expect_ok (complete client ()));
      Alcotest.(check bool)
        "no response_format member" false
        (has_member "response_format" (jbody server)))

let test_request_round_trip () =
  (* ^nchat-6kd8 ^nchat-02vr: the request the client writes is the type's own, read
     back. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore
        (expect_ok
           (complete client ~max_tokens:32 ~json_object:true ~reasoning:(`Effort "low") ()));
      match Types.request_of_yojson (jbody server) with
      | Error message -> Alcotest.failf "the request does not decode: %s" message
      | Ok request ->
          Alcotest.(check (option int)) "max_tokens" (Some 32) request.Types.max_tokens;
          Alcotest.(check bool)
            "response_format" true
            (Option.is_some request.Types.response_format);
          Alcotest.(check (option string))
            "effort" (Some "low")
            (Option.bind request.Types.reasoning (fun reasoning -> reasoning.Types.effort)))

(* Every refusal below is one broken reply served once: the client must refuse it, name
   the offending value, and not retry. *)
let refusal where body =
  run (fun ~sw env ->
      let server = Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ body ] in
      let client = client ~sw env server () in
      let error = expect_error (complete client ()) in
      Alcotest.(check int) "one attempt" 1 (Chat_server.connections server);
      Alcotest.(check bool)
        ("^nchat-wtog " ^ where ^ " is not retryable")
        false
        (Eta_ai.Error.retryable error);
      error)

let expect_message needle error =
  Alcotest.(check bool)
    ("the error names " ^ needle) true
    (contains (Eta_ai.Error.to_string error) needle)

let test_no_choices () =
  (* ^nchat-wtog: a reply that names no completion is refused, not defaulted. *)
  expect_message "choice"
    (refusal "empty choices"
       {|{"model":"inception/mercury-2.5","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}|})

let test_missing_usage () =
  (* ^nchat-wtog: usage is required, so a reply without it is not read as zero. *)
  expect_message "usage"
    (refusal "missing usage"
       {|{"model":"inception/mercury-2.5","choices":[{"message":{"role":"assistant","content":"{}"},"finish_reason":"stop"}]}|})

let test_wrong_usage_type () =
  expect_message "prompt_tokens"
    (refusal "wrong usage type"
       {|{"model":"inception/mercury-2.5","choices":[{"message":{"role":"assistant","content":"{}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":"many","completion_tokens":3,"total_tokens":14}}|})

let test_null_content () =
  (* ^nchat-wtog: a null content is not an empty string. *)
  expect_message "content"
    (refusal "null content"
       {|{"model":"inception/mercury-2.5","choices":[{"message":{"role":"assistant","content":null},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}|})

let test_malformed_json () =
  expect_message "malformed JSON" (refusal "malformed JSON" {|{"choices":|})

let test_statuses () =
  (* ^nchat-wtog: the transport's status mapping is the contract's, not a client's. *)
  let cases =
    [
      (401, "authentication failed", "invalid response");
      (400, "invalid response", "authentication failed");
      (500, "unavailable", "invalid response");
    ]
  in
  List.iter
    (fun (status, expected, unexpected) ->
      run (fun ~sw env ->
          let server =
            Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
              (Chat_server.ok ~status ~reason:"Status" {|{"error":"no"}|})
          in
          let client = client ~sw env server () in
          let error = expect_error (complete client ()) in
          Alcotest.(check int) "one attempt" 1 (Chat_server.connections server);
          let text = Eta_ai.Error.to_string error in
          Alcotest.(check bool)
            (Printf.sprintf "%d says %s" status expected)
            true (contains text expected);
          Alcotest.(check bool)
            (Printf.sprintf "%d does not say %s" status unexpected)
            false (contains text unexpected)))
    cases

let test_429_retries () =
  (* ^nchat-wtog: 429 is the retryable status; the second answer is taken. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.ok ~status:429 ~reason:"Too Many Requests"
             {|{"error":"slow down"}|}
          @ Chat_server.ok (Chat_server.reply ()))
      in
      let client = client ~sw env server () in
      let completion = expect_ok (complete client ()) in
      Alcotest.(check int) "two attempts" 2 (Chat_server.connections server);
      expect_content {|{"text":"ada"}|} completion)

let test_429_exhausted () =
  (* ^nchat-wtog: two 429s are two attempts, and the failure is retryable. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.ok ~status:429 ~reason:"Too Many Requests"
             {|{"error":"slow down"}|}
          @ Chat_server.ok ~status:429 ~reason:"Too Many Requests"
              {|{"error":"slow down"}|})
      in
      let client = client ~sw env server () in
      let error = expect_error (complete client ()) in
      Alcotest.(check int) "exactly two attempts" 2 (Chat_server.connections server);
      Alcotest.(check bool) "^nchat-wtog retryable" true (Eta_ai.Error.retryable error))

let test_transport_failure_retries () =
  (* ^nchat-wtog: the first attempt fails on the wire, so the second is tried. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.after Eta.Duration.zero Fake_server.Silent
          @ Chat_server.ok (Chat_server.reply ()))
      in
      let client = client ~sw env server () in
      let completion = expect_ok (complete client ()) in
      Alcotest.(check int) "two attempts" 2 (Chat_server.connections server);
      expect_content {|{"text":"ada"}|} completion)

let test_attempt_timeout_is_retryable () =
  (* ^nchat-wtog: both attempts time out inside the deadline; the failure is Timeout. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.after (Eta.Duration.ms 60) Fake_server.Silent
          @ Chat_server.after (Eta.Duration.ms 60) Fake_server.Silent)
      in
      let client = client ~sw env server ~timeout:attempt_timeout () in
      (match complete client () with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Eta_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "a stalled attempt returned an answer");
      Alcotest.(check int) "two attempts" 2 (Chat_server.connections server))

let test_request_bound () =
  (* ^nchat-wtog: over 4 MiB is refused before a socket exists. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      let huge = String.make (4 * 1024 * 1024) 'x' in
      match complete client ~messages:[ user huge ] () with
      | Ok _ -> Alcotest.fail "an oversized request was sent"
      | Error (`Input_too_large { limit; length }) ->
          Alcotest.(check int) "the bound is 4 MiB" (4 * 1024 * 1024) limit;
          Alcotest.(check bool) "the length is over it" true (length > limit);
          Alcotest.(check int) "nothing was sent" 0 (Chat_server.connections server)
      | Error error ->
          Alcotest.failf "not Input_too_large: %s" (Eta_ai.Error.to_string error))

let test_response_bound () =
  (* ^nchat-wtog: over 1 MiB is rejected after one attempt, as the reference's bound read
     ends its call. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [ String.make ((1024 * 1024) + 1) 'x' ]
      in
      let client = client ~sw env server () in
      let error = expect_error (complete client ()) in
      Alcotest.(check int) "one attempt" 1 (Chat_server.connections server);
      Alcotest.(check bool)
        "refused as an invalid response" true
        (contains (Eta_ai.Error.to_string error) "invalid response"))

let test_expired_deadline () =
  (* ^nchat-wtog: a deadline already passed sends nothing. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      match complete client ~deadline:Eta.Duration.zero () with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Eta_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "an expired deadline was ignored")

let test_completion_of_empty_reply () =
  (* ^nchat-wtog: the codec refuses a reply with no choice, so nothing is invented. *)
  let json =
    Yojson.Safe.from_string
      {|{"model":"inception/mercury-2.5","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}|}
  in
  match Types.response_of_yojson json with
  | Error message -> Alcotest.failf "the reply does not decode: %s" message
  | Ok response -> (
      match Codecs.completion_of_response response with
      | Error message ->
          Alcotest.(check bool)
            "the refusal names choices" true (contains message "choice")
      | Ok _ -> Alcotest.fail "a reply without a choice was accepted")

let test_extra_members_ignored () =
  (* ^nchat-wtog: the endpoint is OpenAI-compatible, not OpenAI: the members a reply
     carries beyond the modelled ones do not make it an invalid answer. *)
  match
    Types.response_of_yojson
      (Yojson.Safe.from_string (Chat_server.reply ~content:"{}" ()))
  with
  | Error message -> Alcotest.failf "an OpenAI-compatible reply was refused: %s" message
  | Ok response -> (
      match Codecs.completion_of_response response with
      | Ok completion -> expect_content "{}" completion
      | Error message -> Alcotest.failf "no completion: %s" message)

let test_fake_chat_server () =
  (* ^nchat-kk3g: the fixture scripts one reply per connection and records every request,
     so a story test asserts what the endpoint saw. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [
            Chat_server.reply ~content:{|{"text":"first"}|} ();
            Chat_server.reply ~content:{|{"text":"second"}|} ();
          ]
      in
      let client = client ~sw env server () in
      expect_content {|{"text":"first"}|} (expect_ok (complete client ()));
      expect_content {|{"text":"second"}|} (expect_ok (complete client ()));
      Alcotest.(check int) "one connection per call" 2 (Chat_server.connections server);
      Alcotest.(check int)
        "both requests recorded" 2
        (List.length (Chat_server.requests server));
      Alcotest.(check string)
        "the client's path" Chat_server.path
        (match Option.get (Chat_server.request server) with
        | _, headers, _ -> Option.value (List.assoc_opt "host" headers) ~default:""))

let test_usage_logged () =
  (* ^nchat-96zw: usage reaches the debug log with the request id and the model. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      ignore (expect_ok (complete client ()));
      let records =
        Eta_observability.Logger.Memory.find ~level:Eta_observability.Logger.Debug memory
      in
      let record =
        match
          List.find_opt
            (fun record -> String.equal record.Eta_observability.Logger.msg "chat")
            records
        with
        | Some record -> record
        | None -> Alcotest.fail "no chat usage record"
      in
      let field name =
        match List.assoc_opt name record.Eta_observability.Logger.fields with
        | Some (Eta_observability.Logger.Int value) -> string_of_int value
        | Some (Eta_observability.Logger.String value) -> value
        | Some _ -> Alcotest.failf "field %s has an unexpected shape" name
        | None -> Alcotest.failf "no field %s" name
      in
      Alcotest.(check string) "prompt tokens" "11" (field "prompt_tokens");
      Alcotest.(check string) "completion tokens" "3" (field "completion_tokens");
      Alcotest.(check string) "total tokens" "14" (field "total_tokens");
      Alcotest.(check string) "request id" "gen-chat-1" (field "request_id");
      Alcotest.(check string) "model" chat_model (field "model"))

let test_key_never_logged () =
  (* The key travels as a redacted value; a debug log cannot show it. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      ignore (expect_ok (complete client ()));
      let lines =
        Eta_observability.Logger.Memory.records memory
        |> List.map Eta_observability.Logger.to_string
      in
      Alcotest.(check bool)
        "the key is not in the log" false
        (List.exists
           (fun line -> contains line (Eta_observability.Redact.expose chat_key))
           lines))

let () =
  Alcotest.run "AI chat"
    [
      ( "complete",
        [
          Alcotest.test_case "^nchat-dys0 one call returns content and usage" `Quick
            test_complete;
          Alcotest.test_case "^nchat-6kd8 reasoning disabled" `Quick
            test_reasoning_disabled;
          Alcotest.test_case "^nchat-6kd8 reasoning effort" `Quick test_reasoning_effort;
          Alcotest.test_case "^nchat-6kd8 reasoning omitted" `Quick test_reasoning_omitted;
          Alcotest.test_case "^nchat-02vr json_object" `Quick test_json_object;
          Alcotest.test_case "^nchat-02vr json_object omitted" `Quick
            test_json_object_omitted;
          Alcotest.test_case "^nchat-6kd8 the request is the type's own" `Quick
            test_request_round_trip;
        ] );
      ( "fail-closed",
        [
          Alcotest.test_case "^nchat-wtog empty choices" `Quick test_no_choices;
          Alcotest.test_case "^nchat-wtog missing usage" `Quick test_missing_usage;
          Alcotest.test_case "^nchat-wtog wrong usage type" `Quick test_wrong_usage_type;
          Alcotest.test_case "^nchat-wtog null content" `Quick test_null_content;
          Alcotest.test_case "^nchat-wtog malformed JSON" `Quick test_malformed_json;
          Alcotest.test_case "^nchat-wtog status mapping" `Quick test_statuses;
          Alcotest.test_case "^nchat-wtog 429 then success" `Quick test_429_retries;
          Alcotest.test_case "^nchat-wtog 429 twice" `Quick test_429_exhausted;
          Alcotest.test_case "^nchat-wtog transport failure retries" `Quick
            test_transport_failure_retries;
          Alcotest.test_case "^nchat-wtog attempt timeout is retryable" `Quick
            test_attempt_timeout_is_retryable;
          Alcotest.test_case "^nchat-wtog request over 4 MiB" `Quick test_request_bound;
          Alcotest.test_case "^nchat-wtog response over 1 MiB" `Quick test_response_bound;
          Alcotest.test_case "^nchat-wtog expired deadline" `Quick test_expired_deadline;
          Alcotest.test_case "^nchat-wtog the completion codec refuses emptiness" `Quick
            test_completion_of_empty_reply;
          Alcotest.test_case "^nchat-wtog extra reply members are ignored" `Quick
            test_extra_members_ignored;
        ] );
      ( "fixture",
        [
          Alcotest.test_case "^nchat-kk3g the fake chat server scripts replies" `Quick
            test_fake_chat_server;
        ] );
      ( "observability",
        [
          Alcotest.test_case "^nchat-96zw usage logged at debug" `Quick test_usage_logged;
          Alcotest.test_case "^nchat-wtog the key is never logged" `Quick
            test_key_never_logged;
        ] );
      ( "live",
        [
          Alcotest.test_case "^nchat-kk3g live smoke (opt-in)" `Quick Test_chat_live.smoke;
        ] );
    ]
