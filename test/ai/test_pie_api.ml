(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
(* Pie consumer regressions: ^oxpie-a4m7 ^oxpie-b6q2 ^oxpie-c8r5 ^oxpie-d3t9
   ^oxpie-e5v1 ^oxpie-f7w4. All HTTP calls target switch-owned loopback servers. *)
module R = Ox_ai_openrouter.Responses
module A = Ox_ai_openrouter.Audio
module H = Test_helpers

(* ^safe-p9cw: elapsed assertions share the operation’s monotonic clock. *)
let elapsed clock start =
  Mtime.Span.to_float_ns (Mtime.span start (Eio.Time.Mono.now clock)) /. 1e9

let key = Ox_observability.Redact.make "pie-fake-key"
let deadline = Ox.Duration.seconds 3
let ok = H.expect_ok

let audio : R.request =
  {
    model = "gemini-test";
    prompt = "The recording follows.";
    wav = Bytes.of_string "ID3";
    temperature = Some 0.2;
    text_format = None;
    reasoning_effort = Some "low";
  }

let text : R.text_request =
  {
    model = "gemini-test";
    instructions = "Correct the rendered glossary prompt.";
    input = "helo world";
    temperature = Some 0.2;
    text_format = None;
    reasoning_effort = Some "low";
  }

let transcription : A.request =
  {
    model = "transcribe-test";
    filename = "sample.wav";
    wav = Bytes.of_string "RIFF";
    language = None;
    prompt = None;
    temperature = None;
  }

let reply =
  {|{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"hello world"}]}]}|}

let setup ~sw env scripts =
  let server = Fake_server.serve ~net:env#net ~clock:env#clock ~sw scripts in
  let http = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
  let logger = fst (H.memory_logger env) in
  (server, http, logger)

let check_delivered what expected response =
  match R.deliverable response with
  | Ok value -> Alcotest.(check string) what expected value
  | Error _ -> Alcotest.failf "%s: response was not deliverable" what

let test_audio_formats () =
  H.run (fun ~sw env ->
      List.iter
        (fun (format, expected) ->
          let server, http, logger = setup ~sw env (Fake_server.ok reply) in
          let response =
            ok
              (R.create ~http ~clock:env#clock ~logger ~api_key:key
                 ~endpoint:(Fake_server.url server "/responses")
                 ?audio_format:format ~instructions:text.instructions ~deadline audio)
          in
          check_delivered "only message text" "hello world" response;
          let sent = H.jbody server in
          Alcotest.(check string)
            "separate instructions" text.instructions
            (H.text_of (H.member "instructions" sent));
          let messages = H.list_of (H.member "input" sent) in
          Alcotest.(check int) "one user message" 1 (List.length messages);
          let message =
            match messages with
            | head :: _ -> head
            | [] -> Alcotest.fail "missing ai/test_pie_api fixture: messages"
          in
          Alcotest.(check string) "role" "user" (H.text_of (H.member "role" message));
          let parts = H.list_of (H.member "content" message) in
          Alcotest.(check string)
            "input text" audio.prompt
            (H.text_of
               (H.member "text"
                  (match parts with
                  | head :: _ -> head
                  | [] -> Alcotest.fail "missing ai/test_pie_api fixture: parts")));
          let part =
            H.member "input_audio"
              (match parts with
              | _ :: value :: _ -> value
              | _ -> Alcotest.fail "missing ai/test_pie_api fixture: parts element 1")
          in
          Alcotest.(check string)
            "selected format" expected
            (H.text_of (H.member "format" part));
          Alcotest.(check string) "same bytes" "SUQz" (H.text_of (H.member "data" part));
          Alcotest.(check int) "one request" 1 (Fake_server.connections server))
        [ (None, "wav"); (Some R.Wav, "wav"); (Some R.Mp3, "mp3") ])

let test_text_request () =
  H.run (fun ~sw env ->
      List.iter
        (fun effort ->
          let request = { text with reasoning_effort = effort } in
          let server, http, logger = setup ~sw env (Fake_server.ok reply) in
          let response =
            ok
              (R.create_text ~http ~clock:env#clock ~logger ~api_key:key
                 ~endpoint:(Fake_server.url server "/responses")
                 ~deadline request)
          in
          check_delivered "shared deliverable" "hello world" response;
          Alcotest.(check bool)
            "reasoning remains available" true
            (List.mem (R.Other "reasoning") response.output);
          let sent = H.jbody server in
          Alcotest.(check string)
            "instructions" request.instructions
            (H.text_of (H.member "instructions" sent));
          let messages = H.list_of (H.member "input" sent) in
          Alcotest.(check int) "one user message" 1 (List.length messages);
          let message =
            match messages with
            | head :: _ -> head
            | [] -> Alcotest.fail "missing ai/test_pie_api fixture: messages"
          in
          Alcotest.(check string) "user role" "user" (H.text_of (H.member "role" message));
          let parts = H.list_of (H.member "content" message) in
          Alcotest.(check int) "no audio" 1 (List.length parts);
          let first_part =
            match parts with
            | first_part :: _ -> first_part
            | [] -> Alcotest.fail "missing encoded text part fixture"
          in
          Alcotest.(check string)
            "input_text" "input_text"
            (H.text_of (H.member "type" first_part));
          Alcotest.(check string)
            "user input" request.input
            (H.text_of (H.member "text" first_part));
          Alcotest.(check string)
            "temperature" "0.2"
            (Yojson.Safe.to_string (H.member "temperature" sent));
          Alcotest.(check bool) "non-streaming" true (H.member "stream" sent = `Bool false);
          match effort with
          | Some expected ->
              Alcotest.(check string)
                "reasoning effort" expected
                (H.text_of (H.member "effort" (H.member "reasoning" sent)))
          | None ->
              Alcotest.(check bool)
                "optional reasoning omitted" false
                (Ox_json.member "reasoning" sent <> None))
        [ Some "low"; None ];
      let server, http, logger = setup ~sw env (Fake_server.ok reply) in
      let create request =
        R.create_text ~http ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/responses")
          ~deadline request
      in
      List.iter
        (fun request ->
          match create request with
          | Error (`Invalid_response _) -> ()
          | _ -> Alcotest.fail "invalid text request accepted")
        [
          { text with model = "" };
          { text with instructions = "" };
          { text with input = "" };
          { text with temperature = Some Float.nan };
          { text with temperature = Some Float.infinity };
        ];
      Alcotest.(check int)
        "invalid text rejected before I/O" 0
        (Fake_server.connections server))

let test_reasoning_verdict () =
  H.run (fun ~sw env ->
      let response suffix =
        let body =
          {|{"status":"completed","output":[{"type":"reasoning","summary":[]},|} ^ suffix
          ^ "]}"
        in
        let server, http, logger = setup ~sw env (Fake_server.ok body) in
        ok
          (R.create_text ~http ~clock:env#clock ~logger ~api_key:key
             ~endpoint:(Fake_server.url server "/responses")
             ~deadline text)
      in
      let tool = response {|{"type":"function_call","name":"lookup","call_id":"c1"}|} in
      (match R.deliverable tool with
      | Error (`Tool_continuation _) -> ()
      | _ -> Alcotest.fail "reasoning cannot hide a tool call");
      let refusal = response {|{"type":"refusal","refusal":"no"}|} in
      (match R.deliverable refusal with
      | Error (`Refusal "no") -> ()
      | _ -> Alcotest.fail "reasoning cannot hide a refusal");
      let other = response {|{"type":"unknown"}|} in
      (match R.deliverable other with
      | Error (`Other "unknown") -> ()
      | _ -> Alcotest.fail "unknown kinds still refuse");
      let incomplete = { tool with status = "incomplete" } in
      match R.deliverable incomplete with
      | Error (`Not_completed "incomplete") -> ()
      | _ -> Alcotest.fail "status still refuses before kinds")

let check_over_bound ~limit ~length = function
  | Error (`Input_too_large actual) ->
      Alcotest.(check int) "effective bound" limit actual.Ox_json.limit;
      Alcotest.(check int) "complete encoded length" length actual.Ox_json.length
  | Error error -> Alcotest.failf "wrong refusal: %s" (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.fail "oversize request accepted"

let test_request_bounds () =
  H.run (fun ~sw env ->
      let server, http, logger = setup ~sw env (Fake_server.ok reply) in
      let length = Bytes.length (Ox_ai.Transport.bytes_of_json (R.encode audio)) in
      let create ?max_request_bytes () =
        R.create ~http ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/responses")
          ?max_request_bytes ~deadline audio
      in
      check_over_bound ~limit:(length - 1) ~length
        (create ~max_request_bytes:(length - 1) ());
      Alcotest.(check int) "refused before connecting" 0 (Fake_server.connections server);
      check_delivered "at complete JSON bound" "hello world"
        (ok (create ~max_request_bytes:length ()));
      let server, http, logger = setup ~sw env (Fake_server.ok reply) in
      check_delivered "below complete JSON bound" "hello world"
        (ok
           (R.create ~http ~clock:env#clock ~logger ~api_key:key
              ~endpoint:(Fake_server.url server "/responses")
              ~max_request_bytes:(length + 1) ~deadline audio));
      let large = { audio with wav = Bytes.make ((3 * 1024 * 1024) + 1000) 'R' } in
      let length = Bytes.length (Ox_ai.Transport.bytes_of_json (R.encode large)) in
      let server, http, logger = setup ~sw env (Fake_server.ok reply) in
      let create ?max_request_bytes () =
        R.create ~http ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/responses")
          ?max_request_bytes ~deadline large
      in
      check_over_bound ~limit:Ox_ai.Transport.default_max_request_bytes ~length
        (create ());
      Alcotest.(check int)
        "default refusal opened no connection" 0
        (Fake_server.connections server);
      ignore (ok (create ~max_request_bytes:length ()));
      Alcotest.(check int)
        "raised bound sends whole body" length
        (String.length (Fake_server.body server));
      let server, http, logger = setup ~sw env (Fake_server.ok ~status:413 "too large") in
      let length = Bytes.length (Ox_ai.Transport.bytes_of_json (R.encode_text text)) in
      check_over_bound ~limit:9000 ~length
        (R.create_text ~http ~clock:env#clock ~logger ~api_key:key
           ~endpoint:(Fake_server.url server "/responses")
           ~max_request_bytes:9000 ~deadline text);
      let server, http, _ = setup ~sw env (Fake_server.ok ~status:413 "too large") in
      let length = Bytes.length (ok (A.body transcription)) in
      check_over_bound ~limit:9000 ~length
        (A.create ~http ~api_key:key
           ~endpoint:(Fake_server.url server "/audio/transcriptions")
           ~max_request_bytes:9000 ~deadline transcription))

let test_text_bounds_and_response_caps () =
  H.run (fun ~sw env ->
      let length = Bytes.length (Ox_ai.Transport.bytes_of_json (R.encode_text text)) in
      let server, http, logger = setup ~sw env (Fake_server.ok reply) in
      let create max_request_bytes =
        R.create_text ~http ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/responses")
          ~max_request_bytes ~deadline text
      in
      check_over_bound ~limit:(length - 1) ~length (create (length - 1));
      Alcotest.(check int)
        "text bound refuses before I/O" 0
        (Fake_server.connections server);
      check_delivered "text at full JSON bound" "hello world" (ok (create length));
      List.iter
        (fun text_only ->
          let create server http logger max_response_bytes =
            if text_only then
              R.create_text ~http ~clock:env#clock ~logger ~api_key:key
                ~endpoint:(Fake_server.url server "/responses")
                ~max_response_bytes ~deadline text
            else
              R.create ~http ~clock:env#clock ~logger ~api_key:key
                ~endpoint:(Fake_server.url server "/responses")
                ~max_response_bytes ~deadline audio
          in
          let length = String.length reply in
          let server, http, logger = setup ~sw env (Fake_server.ok reply) in
          (match create server http logger (length - 1) with
          | Error (`Invalid_response issue) ->
              H.expect_part issue.Ox_json.message
                (string_of_int (length - 1) ^ "-byte bound")
          | _ -> Alcotest.fail "response bound was not enforced");
          Alcotest.(check int)
            "oversize response never retries" 1
            (Fake_server.connections server);
          let server, http, logger = setup ~sw env (Fake_server.ok reply) in
          check_delivered "response at exact bound" "hello world"
            (ok (create server http logger length)))
        [ false; true ])

let check_timeout = function
  | Error `Timeout -> ()
  | Error error -> Alcotest.failf "expected timeout: %s" (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.fail "stalled response completed"

let fragmented body =
  let length = String.length body in
  let head =
    Printf.sprintf "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
      length
  in
  let pieces =
    List.init 5 (fun i ->
        let start = i * length / 5 and stop = (i + 1) * length / 5 in
        (Ox.Duration.ms 40, String.sub body start (stop - start)))
  in
  [
    {
      Fake_server.delay = Ox.Duration.zero;
      response = Chunks ((Ox.Duration.zero, head) :: pieces);
    };
  ]

let test_attempt_timeout () =
  H.run (fun ~sw env ->
      List.iter
        (fun text_only ->
          let call ~timeout ~deadline =
            let server, http, logger =
              setup ~sw env (fragmented reply @ fragmented reply)
            in
            if text_only then
              R.create_text ~http ~clock:env#clock ~logger ~api_key:key
                ~endpoint:(Fake_server.url server "/responses")
                ~timeout ~response_idle:(Ox.Duration.ms 120) ~deadline text
            else
              R.create ~http ~clock:env#clock ~logger ~api_key:key
                ~endpoint:(Fake_server.url server "/responses")
                ~timeout ~response_idle:(Ox.Duration.ms 120) ~deadline audio
          in
          check_timeout (call ~timeout:(Ox.Duration.ms 90) ~deadline);
          check_delivered "raised attempt budget permits progressing reply" "hello world"
            (ok (call ~timeout:(Ox.Duration.ms 400) ~deadline));
          check_timeout (call ~timeout:(Ox.Duration.ms 400) ~deadline:(Ox.Duration.ms 90)))
        [ false; true ])

let test_idle_policy ?(text_only = true) ~transcribe () =
  H.run (fun ~sw env ->
      let body = if transcribe then {|{"text":"hello world"}|} else reply in
      let call ~deadline ~response_idle scripts =
        let server, http, logger = setup ~sw env scripts in
        if transcribe then
          A.create ~http ~api_key:key
            ~endpoint:(Fake_server.url server "/transcriptions")
            ~response_idle ~deadline transcription
        else
          (if text_only then
             R.create_text ~http ~clock:env#clock ~logger ~api_key:key
               ~endpoint:(Fake_server.url server "/responses")
               ~response_idle ~deadline text
           else
             R.create ~http ~clock:env#clock ~logger ~api_key:key
               ~endpoint:(Fake_server.url server "/responses")
               ~response_idle ~deadline audio)
          |> Result.map (fun response -> response.R.text)
      in
      let started = Eio.Time.Mono.now env#mono_clock in
      check_timeout
        (call ~deadline ~response_idle:(Ox.Duration.ms 60)
           (Fake_server.after (Ox.Duration.seconds 2)
              (Fake_server.Response (Fake_server.http_response body))));
      Alcotest.(check bool)
        "headers stall cut before total deadline" true
        (elapsed env#mono_clock started < 1.5);
      let head =
        Printf.sprintf "HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n"
          (String.length body)
      in
      let started = Eio.Time.Mono.now env#mono_clock in
      check_timeout
        (call ~deadline ~response_idle:(Ox.Duration.ms 60)
           [
             {
               Fake_server.delay = Ox.Duration.zero;
               response =
                 Chunks [ (Ox.Duration.zero, head ^ "{"); (Ox.Duration.seconds 2, "}") ];
             };
           ]);
      Alcotest.(check bool)
        "body stall cut before total deadline" true
        (elapsed env#mono_clock started < 1.5);
      let started = Eio.Time.Mono.now env#mono_clock in
      Alcotest.(check string)
        "progress resets idle timer" "hello world"
        (ok (call ~deadline ~response_idle:(Ox.Duration.ms 120) (fragmented body)));
      Alcotest.(check bool)
        "progress survives longer than one idle window" true
        (elapsed env#mono_clock started > 0.16);
      check_timeout
        (call ~deadline:(Ox.Duration.ms 90) ~response_idle:(Ox.Duration.ms 120)
           (fragmented body)))

let () =
  Alcotest.run "Pie provider API gaps"
    [
      ( "offline",
        [
          Alcotest.test_case "WAV/MP3 ^oxpie-a4m7" `Quick test_audio_formats;
          Alcotest.test_case "text-only wire ^oxpie-d3t9" `Quick test_text_request;
          Alcotest.test_case "reasoning verdict ^oxpie-c8r5" `Quick test_reasoning_verdict;
          Alcotest.test_case "request bounds ^oxpie-b6q2" `Quick test_request_bounds;
          Alcotest.test_case "text/response bounds ^oxpie-b6q2 ^oxpie-d3t9" `Quick
            test_text_bounds_and_response_caps;
          Alcotest.test_case "Responses attempt/total budgets ^oxpie-e5v1" `Quick
            test_attempt_timeout;
          Alcotest.test_case "Responses progress ^oxpie-e5v1" `Quick
            (test_idle_policy ~transcribe:false);
          Alcotest.test_case "audio Responses progress ^oxpie-e5v1" `Quick
            (test_idle_policy ~text_only:false ~transcribe:false);
          Alcotest.test_case "transcription progress ^oxpie-f7w4" `Quick
            (test_idle_policy ~transcribe:true);
        ] );
    ]
