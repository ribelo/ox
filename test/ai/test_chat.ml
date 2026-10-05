(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
(* Story tests for the chat client against the fake chat server (^nchat-kk3g).

   ^nchat-dys0: one call returns the first choice's content and usage. ^nchat-6kd8: the
   reasoning control is written in the two forms OpenRouter documents and omitted when the
   caller says nothing. ^nchat-02vr: `~json_object:true` requires a JSON object.
   ^nchat-wtog: decoding, bounds, the two-attempt policy and the typed errors are the
   System One client's, because both share {!Ox_ai}. ^nchat-96zw: usage at debug.
   ^nchat-qu3j: the provider's own cost is read beside the tokens when it reports one. *)

open Chat_helpers
module Codecs = Ox_ai_chat.Codecs
module Types = Ox_ai_chat.Types

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
      let method_, headers, _ =
        match Chat_server.request server with
        | Some value -> value
        | None ->
            Alcotest.fail "missing ai/test_chat fixture: (Chat_server.request server)"
      in
      Alcotest.(check string) "method" "POST" method_;
      Alcotest.(check (option string))
        "path" (Some Chat_server.path)
        (List.assoc_opt "host" headers);
      Alcotest.(check (option string))
        "bearer header"
        (Some ("Bearer " ^ Ox_observability.Redact.expose chat_key))
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
      let system_message, user_message =
        match sent with
        | system_message :: user_message :: _ -> (system_message, user_message)
        | _ -> Alcotest.fail "missing encoded system/user message fixtures"
      in
      Alcotest.(check string)
        "system role" "system"
        (text_of (member "role" system_message));
      Alcotest.(check string)
        "system content" "Answer with one JSON object."
        (text_of (member "content" system_message));
      Alcotest.(check string) "user role" "user" (text_of (member "role" user_message));
      Alcotest.(check string)
        "user content" {|{"goal":"type ada"}|}
        (text_of (member "content" user_message));
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

(* ^nchat-qu3j: the reply shape the cost story is about — the same OpenAI-compatible reply
   with the usage object spelled out, so a test says exactly which members the provider
   sent. *)
let usage_reply usage =
  Printf.sprintf
    {|{"id":"gen-chat-1","model":"inception/mercury-2.5","choices":[{"message":{"role":"assistant","content":"{}"},"finish_reason":"stop"}],"usage":%s}|}
    usage

let test_usage_cost () =
  (* ^nchat-qu3j: the provider's own cost reaches the caller beside the tokens, as the
     number the wire carries — OpenRouter writes a fraction for a paid completion and the
     integer zero for a free one. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [
            usage_reply
              {|{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14,"cost":0.00042}|};
            usage_reply
              {|{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14,"cost":0}|};
          ]
      in
      let client = client ~sw env server () in
      let paid = expect_ok (complete client ()) in
      Alcotest.(check (option (float 0.)))
        "the reported cost" (Some 0.00042) paid.Codecs.usage.cost;
      Alcotest.(check int) "the tokens still read" 14 paid.Codecs.usage.total_tokens;
      let free = expect_ok (complete client ()) in
      Alcotest.(check (option (float 0.)))
        "an integer cost is the same number" (Some 0.) free.Codecs.usage.cost)

let test_usage_cost_absent () =
  (* ^nchat-qu3j: a provider that reports no cost is not sending an invalid answer — a
     chat endpoint is OpenAI-compatible and not OpenRouter — so the caller reads None,
     never zero, and the reply's tokens still decode. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [
            usage_reply {|{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14}|};
            usage_reply
              {|{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14,"cost":null}|};
          ]
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      let absent = expect_ok (complete client ()) in
      Alcotest.(check (option (float 0.)))
        "no reported cost" None absent.Codecs.usage.cost;
      Alcotest.(check int) "the tokens still read" 14 absent.Codecs.usage.total_tokens;
      let logged =
        Ox_observability.Logger.Memory.find ~level:Ox_observability.Logger.Debug memory
        |> List.filter (fun record ->
            String.equal record.Ox_observability.Logger.msg "chat")
      in
      (match logged with
      | record :: _ ->
          Alcotest.(check bool)
            "no cost field in the log" false
            (List.mem_assoc "cost" record.Ox_observability.Logger.fields)
      | [] -> Alcotest.fail "no chat usage record");
      let null = expect_ok (complete client ()) in
      Alcotest.(check (option (float 0.)))
        "a null cost is no cost" None null.Codecs.usage.cost)

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
        false (Ox_ai.Error.retryable error);
      error)

let expect_message needle error =
  Alcotest.(check bool)
    ("the error names " ^ needle) true
    (contains (Ox_ai.Error.to_string error) needle)

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

let test_usage_cost_wrong_type () =
  (* ^nchat-qu3j: the cost is read fail-closed like every other member the client acts on
     — a cost that is not a number is refused with its path, not ignored (^nchat-wtog). *)
  expect_message "usage.cost"
    (refusal "a non-numeric cost"
       (usage_reply
          {|{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14,"cost":"free"}|}))

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
          let text = Ox_ai.Error.to_string error in
          Alcotest.(check bool)
            (Printf.sprintf "%d says %s" status expected)
            true (contains text expected);
          Alcotest.(check bool)
            (Printf.sprintf "%d does not say %s" status unexpected)
            false (contains text unexpected)))
    cases

let test_429_no_replay () =
  (* ^safe-a5mq: 429 remains retryable in the error, not replay permission. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.ok ~status:429 ~reason:"Too Many Requests"
             {|{"error":"slow down"}|}
          @ Chat_server.ok (Chat_server.reply ()))
      in
      let client = client ~sw env server () in
      let error = expect_error (complete client ()) in
      Alcotest.(check int) "^safe-o2b6 one attempt" 1 (Chat_server.connections server);
      match error with
      | `Unavailable { retryable = true; _ } -> ()
      | _ -> Alcotest.fail "^safe-a5mq expected unchanged Unavailable classification")

let test_429_classification () =
  (* ^safe-a5mq: the error classification does not authorize a second POST. *)
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
      Alcotest.(check int)
        "^safe-a5mq no retry despite status" 1
        (Chat_server.connections server);
      Alcotest.(check bool) "^nchat-wtog retryable" true (Ox_ai.Error.retryable error))

let test_transport_failure_no_replay () =
  (* ^safe-o2b6: ambiguous transport failure is not automatically repeated. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.after Ox.Duration.zero Fake_server.Silent
          @ Chat_server.ok (Chat_server.reply ()))
      in
      let client = client ~sw env server () in
      let error = expect_error (complete client ()) in
      Alcotest.(check int) "^safe-o2b6 one attempt" 1 (Chat_server.connections server);
      match error with
      | `Unavailable { retryable = true; _ } -> ()
      | _ -> Alcotest.fail "^safe-a5mq expected unchanged Unavailable classification")

let test_attempt_timeout_no_replay () =
  (* ^safe-3o27: one attempt times out inside the deadline; no replay follows. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve_scripts ~net:env#net ~clock:env#clock ~sw
          (Chat_server.after (Ox.Duration.ms 60) Fake_server.Silent
          @ Chat_server.after (Ox.Duration.ms 60) Fake_server.Silent)
      in
      let client = client ~sw env server ~timeout:attempt_timeout () in
      (match complete client () with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Ox_ai.Error.to_string error)
      | Ok _ -> Alcotest.fail "a stalled attempt returned an answer");
      Alcotest.(check int)
        "^safe-3o27 no retry after timeout" 1
        (Chat_server.connections server))

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
          Alcotest.failf "not Input_too_large: %s" (Ox_ai.Error.to_string error))

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
        (contains (Ox_ai.Error.to_string error) "invalid response"))

let test_expired_deadline () =
  (* ^nchat-wtog: a deadline already passed sends nothing. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      match complete client ~deadline:Ox.Duration.zero () with
      | Error `Timeout -> ()
      | Error error -> Alcotest.failf "not Timeout: %s" (Ox_ai.Error.to_string error)
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
        (match
           match Chat_server.request server with
           | Some value -> value
           | None ->
               Alcotest.fail "missing ai/test_chat fixture: (Chat_server.request server)"
         with
        | _, headers, _ -> Option.value (List.assoc_opt "host" headers) ~default:""))

let test_usage_logged () =
  (* ^nchat-96zw ^nchat-qu3j: usage — and the provider's own cost, when it reports one —
     reaches the debug log with the request id and the model. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let logger, memory = memory_logger env in
      let client = client ~sw env server ~logger () in
      ignore (expect_ok (complete client ()));
      let records =
        Ox_observability.Logger.Memory.find ~level:Ox_observability.Logger.Debug memory
      in
      let record =
        match
          List.find_opt
            (fun record -> String.equal record.Ox_observability.Logger.msg "chat")
            records
        with
        | Some record -> record
        | None -> Alcotest.fail "no chat usage record"
      in
      let field name =
        match List.assoc_opt name record.Ox_observability.Logger.fields with
        | Some (Ox_observability.Logger.Int value) -> string_of_int value
        | Some (Ox_observability.Logger.String value) -> value
        | Some _ -> Alcotest.failf "field %s has an unexpected shape" name
        | None -> Alcotest.failf "no field %s" name
      in
      Alcotest.(check string) "prompt tokens" "11" (field "prompt_tokens");
      Alcotest.(check string) "completion tokens" "3" (field "completion_tokens");
      Alcotest.(check string) "total tokens" "14" (field "total_tokens");
      let float_field name =
        match List.assoc_opt name record.Ox_observability.Logger.fields with
        | Some (Ox_observability.Logger.Float value) -> value
        | Some _ -> Alcotest.failf "field %s has an unexpected shape" name
        | None -> Alcotest.failf "no field %s" name
      in
      Alcotest.(check (float 0.)) "cost" 0.00002 (float_field "cost");
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
        Ox_observability.Logger.Memory.records memory
        |> List.map Ox_observability.Logger.to_string
      in
      Alcotest.(check bool)
        "the key is not in the log" false
        (List.exists
           (fun line -> contains line (Ox_observability.Redact.expose chat_key))
           lines))

(* ^nimg-4k7p: images select a part array without changing text/image order. *)
let image_message : Types.message =
  {
    role = Types.User;
    content =
      [
        Types.Text "Describe the first image.";
        Types.Image_url "https://example.test/first.png";
        Types.Text "Compare it with this screenshot.";
        Types.image_png (Bytes.of_string "\137PNG\r\n\026\n");
      ];
  }

let test_image_wire () =
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw [ Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      ignore
        (expect_ok
           (complete client ~messages:[ system; image_message ] ~max_tokens:32
              ~json_object:true ~reasoning:`Disabled ()));
      Alcotest.(check string)
        "exact compact image request, preserving all four parts"
        {|{"model":"inception/mercury-2.5","messages":[{"role":"system","content":"Answer with one JSON object."},{"role":"user","content":[{"type":"text","text":"Describe the first image."},{"type":"image_url","image_url":{"url":"https://example.test/first.png"}},{"type":"text","text":"Compare it with this screenshot."},{"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgo="}}]}],"max_tokens":32,"response_format":{"type":"json_object"},"reasoning":{"enabled":false}}|}
        (Chat_server.last_body server))

let test_png_data_url () =
  (* ^nimg-b2u8: exact binary base64, including zero, one and two padding characters. *)
  List.iter
    (fun (input, base64) ->
      let png = Bytes.of_string input in
      let expected = "data:image/png;base64," ^ base64 in
      Alcotest.(check string) "exact data URL" expected (Types.png_data_url png);
      (match Types.image_png png with
      | Types.Image_url url -> Alcotest.(check string) "PNG image part" expected url
      | Types.Text _ -> Alcotest.fail "PNG constructor returned a text part");
      Alcotest.(check string) "input bytes untouched" input (Bytes.to_string png))
    [
      ("", "");
      ("\000", "AA==");
      ("\000\255", "AP8=");
      ("\000\255\128", "AP+A");
      ("\137PNG\r\n\026\n", "iVBORw0KGgo=");
    ]

let test_text_wire_unchanged () =
  (* ^nimg-t9q3: a text builder and adjacent text parts send the old exact bytes. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [ Chat_server.reply (); Chat_server.reply (); Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      let expected =
        {|{"model":"inception/mercury-2.5","messages":[{"role":"system","content":"Answer with one JSON object."},{"role":"user","content":"{\"goal\":\"type ada\"}"}]}|}
      in
      ignore (expect_ok (complete client ()));
      Alcotest.(check string)
        "the old text request bytes" expected
        (Chat_server.last_body server);
      let split : Types.message =
        {
          role = Types.User;
          content = [ Types.Text {|{"goal":|}; Types.Text {|"type ada"}|} ];
        }
      in
      ignore (expect_ok (complete client ~messages:[ system; split ] ()));
      Alcotest.(check string)
        "adjacent text concatenates" expected
        (Chat_server.last_body server);
      let empty : Types.message = { role = Types.User; content = [] } in
      ignore (expect_ok (complete client ~messages:[ empty ] ()));
      Alcotest.(check string)
        "no parts means an empty string"
        {|{"model":"inception/mercury-2.5","messages":[{"role":"user","content":""}]}|}
        (Chat_server.last_body server))

let test_content_round_trip () =
  (* ^nimg-r6w1: request decoding supports both wire forms, never a reply codec. *)
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [ Chat_server.reply (); Chat_server.reply () ]
      in
      let client = client ~sw env server () in
      List.iter
        (fun messages ->
          ignore
            (expect_ok
               (complete client ~messages ~max_tokens:32 ~json_object:true
                  ~reasoning:(`Effort "low") ()));
          match
            Types.request_of_yojson
              (Yojson.Safe.from_string (Chat_server.last_body server))
          with
          | Error message -> Alcotest.failf "request does not decode: %s" message
          | Ok request ->
              Alcotest.(check bool)
                "parts preserved" true
                (request.Types.messages = messages);
              Alcotest.(check string)
                "decoded request encodes to exactly the original wire"
                (Chat_server.last_body server)
                (Yojson.Safe.to_string (Types.yojson_of_request request)))
        [ chat_messages; [ system; image_message ] ]);
  let request content =
    Yojson.Safe.from_string
      (Printf.sprintf {|{"model":"test","messages":[{"role":"user","content":%s}]}|}
         content)
  in
  (match
     Types.request_of_yojson
       (request {|[{"type":"text","text":"a"},{"type":"text","text":"b"}]|})
   with
  | Ok { messages = [ { content = [ Types.Text "a"; Types.Text "b" ]; _ } ]; _ } -> ()
  | _ -> Alcotest.fail "text-array decoding lost its part boundaries");
  List.iter
    (fun content ->
      match Types.request_of_yojson (request content) with
      | Ok _ -> Alcotest.failf "malformed content decoded: %s" content
      | Error message ->
          Alcotest.(check bool) "error names content" true (contains message "content"))
    [
      "null";
      "42";
      {|["text"]|};
      {|[{}]|};
      {|[{"type":"audio"}]|};
      {|[{"type":"text"}]|};
      {|[{"type":"text","text":null}]|};
      {|[{"type":"image_url"}]|};
      {|[{"type":"image_url","image_url":{}}]|};
      {|[{"type":"image_url","image_url":{"url":42}}]|};
      {|[{"type":"image_url","image_url":{"url":"https://example.test/a.png","detail":"low"}}]|};
    ]

let test_image_complete () =
  (* ^nimg-c8v5: one completion call, existing configured bound, string-only replies. *)
  let messages = [ system; image_message ] in
  let bad_content content =
    Printf.sprintf
      {|{"model":"inception/mercury-2.5","choices":[{"message":%s}],"usage":{"prompt_tokens":11,"completion_tokens":3,"total_tokens":14}}|}
      content
  in
  run (fun ~sw env ->
      let server =
        Chat_server.serve ~net:env#net ~clock:env#clock ~sw
          [
            Chat_server.reply ~content:"A screenshot." ();
            bad_content {|{"role":"assistant","content":[{"type":"text","text":"no"}]}|};
            bad_content {|{"role":"assistant","content":null}|};
            bad_content {|{"role":"assistant"}|};
            Chat_server.reply ~content:"A large screenshot." ();
          ]
      in
      let configured = client ~sw env server ~max_request_bytes:(8 * 1024 * 1024) () in
      let completion = expect_ok (complete configured ~messages ()) in
      expect_content "A screenshot." completion;
      Alcotest.(check int) "image completion usage" 14 completion.usage.total_tokens;
      Alcotest.(check string) "image completion model" chat_model completion.model;
      Alcotest.(check (option string)) "request id" (Some "gen-chat-1") completion.id;
      List.iter
        (fun count ->
          let error = expect_error (complete configured ~messages ()) in
          expect_message "content" error;
          Alcotest.(check bool)
            "bad reply is not retryable" false (Ox_ai.Error.retryable error);
          Alcotest.(check int)
            "one attempt per reply" count
            (Chat_server.connections server))
        [ 2; 3; 4 ];
      let wire_length = String.length (Chat_server.last_body server) in
      let bounded = client ~sw env server ~max_request_bytes:(wire_length - 1) () in
      (match complete bounded ~messages () with
      | Error (`Input_too_large { limit; length }) ->
          Alcotest.(check int) "configured image bound" (wire_length - 1) limit;
          Alcotest.(check int) "serialized image length" wire_length length
      | _ -> Alcotest.fail "image request bypassed the configured byte bound");
      Alcotest.(check int)
        "over-bound image opens no socket" 4
        (Chat_server.connections server);
      (* Base64 expands 3 MiB of input to 4 MiB, before JSON and the data-URL prefix. *)
      let large : Types.message =
        {
          role = Types.User;
          content =
            [
              Types.Text "Describe this PNG.";
              Types.image_png (Bytes.make (3 * 1024 * 1024) '\000');
            ];
        }
      in
      let defaults = client ~sw env server () in
      (match complete defaults ~messages:[ large ] () with
      | Error (`Input_too_large { limit; length }) ->
          Alcotest.(check int) "default stays 4 MiB" (4 * 1024 * 1024) limit;
          Alcotest.(check bool) "image request exceeds default" true (length > limit)
      | _ -> Alcotest.fail "large image unexpectedly passed the default bound");
      Alcotest.(check int)
        "default refusal opens no socket" 4
        (Chat_server.connections server);
      let large_reply = expect_ok (complete configured ~messages:[ large ] ()) in
      expect_content "A large screenshot." large_reply;
      Alcotest.(check int)
        "8 MiB configuration admits the image" 5
        (Chat_server.connections server))

let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.env >) in
  let model = Test_chat_live.model ~caps () in
  let endpoint = Test_chat_live.endpoint ~caps () in
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
          Alcotest.test_case "^nchat-qu3j the provider's cost is read" `Quick
            test_usage_cost;
          Alcotest.test_case "^nchat-qu3j no reported cost reads None" `Quick
            test_usage_cost_absent;
        ] );
      ( "images",
        [
          Alcotest.test_case "^nimg-4k7p exact ordered image request JSON" `Quick
            test_image_wire;
          Alcotest.test_case "^nimg-b2u8 pure PNG data URL and image part" `Quick
            test_png_data_url;
          Alcotest.test_case "^nimg-t9q3 text-only request bytes unchanged" `Quick
            test_text_wire_unchanged;
          Alcotest.test_case "^nimg-r6w1 both content forms round-trip fail-closed" `Quick
            test_content_round_trip;
          Alcotest.test_case "^nimg-c8v5 image completion and strict string replies"
            `Quick test_image_complete;
        ] );
      ( "fail-closed",
        [
          Alcotest.test_case "^nchat-wtog empty choices" `Quick test_no_choices;
          Alcotest.test_case "^nchat-wtog missing usage" `Quick test_missing_usage;
          Alcotest.test_case "^nchat-wtog wrong usage type" `Quick test_wrong_usage_type;
          Alcotest.test_case "^nchat-qu3j a non-numeric cost is refused" `Quick
            test_usage_cost_wrong_type;
          Alcotest.test_case "^nchat-wtog null content" `Quick test_null_content;
          Alcotest.test_case "^nchat-wtog malformed JSON" `Quick test_malformed_json;
          Alcotest.test_case "^nchat-wtog status mapping" `Quick test_statuses;
          Alcotest.test_case "^safe-a5mq 429 does not authorize replay" `Quick
            test_429_no_replay;
          Alcotest.test_case "^safe-a5mq 429 classification unchanged" `Quick
            test_429_classification;
          Alcotest.test_case "^safe-o2b6 transport failure does not replay" `Quick
            test_transport_failure_no_replay;
          Alcotest.test_case "^safe-3o27 attempt timeout does not replay" `Quick
            test_attempt_timeout_no_replay;
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
          Alcotest.test_case "^nchat-kk3g live smoke (opt-in)" `Quick
            (Test_chat_live.smoke ~caps ~model ~endpoint);
        ] );
    ]
