(* ^safe-7t06 ^safe-bguw ^safe-35sb ^safe-3osb: missing test fixtures fail explicitly. *)
(* ^air2-rsp1 ^air2-emb2 ^air2-aud3 ^air2-rtm4 ^air2-tst5 ^nor-pn0b ^nor-474w *)
module R = Ox_ai_openrouter.Responses
module E = Ox_ai_openrouter.Embeddings
module A = Ox_ai_openrouter.Audio

let key = Ox_observability.Redact.make "fake-key"
let deadline = Ox.Duration.seconds 3

let request =
  R.
    {
      model = "audio-model";
      prompt = "Transcribe";
      wav = Bytes.of_string "RIFF";
      temperature = Some 0.;
      text_format =
        Some
          (Json_schema
             {
               name = "transcript";
               schema = `Assoc [ ("type", `String "object") ];
               strict = Some true;
             });
      reasoning_effort = Some "low";
    }

let setup ~sw env json =
  let server =
    Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok json)
  in
  let http = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
  let logger = fst (Test_helpers.memory_logger env) in
  (server, http, logger)

let ok = Test_helpers.expect_ok

(* ^nor-pn0b: a decoded reply reports every output item's kind, and [deliverable] is the
   verdict a text caller obeys. Both are rendered to one line, so a failure names the
   shape that arrived. *)
let render_option = function Some value -> value | None -> "<none>"

let pp_output fmt = function
  | R.Output_text text -> Format.fprintf fmt "text %S" text
  | R.Function_call call ->
      Format.fprintf fmt "function_call %s %s" (render_option call.R.name)
        (render_option call.R.call_id)
  | R.Refusal text -> Format.fprintf fmt "refusal %S" text
  | R.Other kind -> Format.fprintf fmt "other %S" kind

let pp_rejection fmt = function
  | `Not_completed status -> Format.fprintf fmt "not completed %s" status
  | `Tool_continuation call ->
      Format.fprintf fmt "tool continuation %s %s" (render_option call.R.name)
        (render_option call.R.call_id)
  | `Refusal text -> Format.fprintf fmt "refusal %s" text
  | `Other kind -> Format.fprintf fmt "other item %s" kind

let rendered pp values = String.concat " | " (List.map (Format.asprintf "%a" pp) values)

let check_outputs what expected (response : R.response) =
  Alcotest.(check string)
    what (rendered pp_output expected)
    (rendered pp_output response.output)

let check_delivered what expected = function
  | Ok text -> Alcotest.(check string) what expected text
  | Error rejection ->
      Alcotest.failf "%s was refused: %s" what
        (Format.asprintf "%a" pp_rejection rejection)

let check_refused what expected = function
  | Error rejection ->
      Alcotest.(check string) what expected (Format.asprintf "%a" pp_rejection rejection)
  | Ok text -> Alcotest.failf "%s was delivered: %S" what text

let test_responses () =
  Test_helpers.run (fun ~sw env ->
      let server, http, logger =
        setup ~sw env
          {|{"id":"r1","model":"audio-model","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"text\":\"hello\"}"}]}]}|}
      in
      let response =
        ok
          (R.create ~http ~clock:env#clock ~logger ~api_key:key
             ~endpoint:(Fake_server.url server "/responses")
             ~deadline request)
      in
      Alcotest.(check string) "status" "completed" response.status;
      Alcotest.(check string) "text" {|{"text":"hello"}|} response.text;
      check_outputs "text-only kind" [ R.Output_text {|{"text":"hello"}|} ] response;
      check_delivered "text-only deliverable" {|{"text":"hello"}|}
        (R.deliverable response);
      let sent = Test_helpers.jbody server in
      let contents =
        Test_helpers.(
          list_of
            (member "content"
               (match list_of (member "input" sent) with
               | head :: _ -> head
               | [] ->
                   Alcotest.fail
                     "missing ai/test_openrouter fixture: (list_of (member \"input\" \
                      sent))")))
      in
      let audio =
        Test_helpers.member "input_audio"
          (match contents with
          | _ :: value :: _ -> value
          | _ -> Alcotest.fail "missing ai/test_openrouter fixture: contents element 1")
      in
      Alcotest.(check string)
        "wav base64" "UklGRg=="
        (Test_helpers.text_of (Test_helpers.member "data" audio));
      Alcotest.(check string)
        "format" "wav"
        (Test_helpers.text_of (Test_helpers.member "format" audio));
      Alcotest.(check bool)
        "no key in request body" false
        (Test_helpers.contains (Fake_server.body server) "fake-key"))

let test_embeddings () =
  Test_helpers.run (fun ~sw env ->
      let server, http, logger =
        setup ~sw env
          {|{"data":[{"index":1,"embedding":[2,3.5]},{"index":0,"embedding":[0.5,1]}],"usage":{"prompt_tokens":3}}|}
      in
      let input = E.Texts [ "one"; "two" ] in
      let response =
        ok
          (E.create ~http ~clock:env#clock ~logger ~api_key:key
             ~endpoint:(Fake_server.url server "/embeddings")
             ~deadline
             E.{ model = "embedding-model"; input; dimensions = Some 2 })
      in
      Alcotest.(check (list int))
        "indices preserved" [ 1; 0 ]
        (List.map (fun (item : E.item) -> item.index) response.embeddings);
      Alcotest.(check (option int)) "tokens" (Some 3) response.input_tokens;
      let sent = Test_helpers.jbody server in
      Alcotest.(check int)
        "dimensions" 2
        (match Test_helpers.member "dimensions" sent with `Int n -> n | _ -> 0))

let test_fail_closed () =
  (match
     E.decode
       (`Assoc
          [
            ( "data",
              `List [ `Assoc [ ("index", `Int 0); ("embedding", `String "base64") ] ] );
          ])
   with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "base64 is not a float vector");
  (match
     R.decode (`Assoc [ ("status", `String "completed"); ("output", `String "bad") ])
   with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "invalid output must fail");
  (match Ox_ai_realtime.Session.decode {|{"type":"conversation.item.created"}|} with
  | Ok event ->
      Alcotest.(check string) "event type" "conversation.item.created" event.kind
  | Error _ -> Alcotest.fail "valid event rejected");
  match Ox_ai_realtime.Session.decode {|{"other":"missing"}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "missing event type accepted"

let test_audio () =
  Test_helpers.run (fun ~sw env ->
      let server, http, _ = setup ~sw env {|{"text":" hello "}|} in
      let result =
        A.create ~http ~api_key:key
          ~endpoint:(Fake_server.url server "/audio/transcriptions")
          ~deadline
          A.
            {
              model = "audio-model";
              filename = "sample.wav";
              wav = Bytes.of_string "RIFF";
              language = Some "en";
              prompt = Some "medical";
              temperature = Some 0.;
            }
      in
      Alcotest.(check string) "transcription" "hello" (ok result);
      let _, headers, body =
        match Fake_server.request server with
        | Some value -> value
        | None ->
            Alcotest.fail
              "missing ai/test_openrouter fixture: (Fake_server.request server)"
      in
      Alcotest.(check bool)
        "multipart header" true
        (Test_helpers.contains
           (match List.assoc_opt "content-type" headers with
           | Some value -> value
           | None ->
               Alcotest.fail "missing ai/test_openrouter fixture: field content-type")
           "multipart/form-data");
      Alcotest.(check bool) "wav bytes" true (Test_helpers.contains body "RIFF");
      Alcotest.(check bool) "prompt" true (Test_helpers.contains body "medical"))

(* Every endpoint maps what a local server can answer: 401 is Authentication, the
   provider's over-size refusal is Input_too_large, a 5xx is Unavailable, and a 2xx body
   that is not the documented JSON is Invalid_response. ^air2-tst5 *)

let check_authentication what = function
  | Error (`Authentication _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_input_too_large what = function
  | Error (`Input_too_large _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_invalid_response what = function
  | Error (`Invalid_response _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_unavailable ~retryable what (result : ('a, Ox_ai.Error.t) result) =
  match result with
  | Error (`Unavailable { retryable = actual; _ }) ->
      Alcotest.(check bool) (what ^ " retryable") retryable actual
  | Error error -> Alcotest.failf "%s: %s" what (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

(* ^nai-97as ^nai-337c ^nai-rjkq: the caller bounds the reply, can ask for one attempt,
   and gets the provider's Retry-After in the typed failure. *)
let test_transport_controls () =
  Test_helpers.run (fun ~sw env ->
      let http () = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
      let logger = fst (Test_helpers.memory_logger env) in
      let embed ?max_response_bytes ?max_attempts server =
        E.create ~http:(http ()) ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/embeddings")
          ?max_response_bytes ?max_attempts ~deadline
          E.{ model = "embedding-model"; input = Text "one"; dimensions = None }
      in
      (* A 1.5 MiB reply: refused under the default 1 MiB bound, read under 4 MiB. *)
      let big =
        let vector = String.concat "," (List.init 200_000 (fun _ -> "0.1234567")) in
        Printf.sprintf {|{"data":[{"index":0,"embedding":[%s]}]}|} vector
      in
      let serve_big () =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok big)
      in
      check_invalid_response "^nai-97as default bound" (embed (serve_big ()));
      (match embed ~max_response_bytes:(4 * 1024 * 1024) (serve_big ()) with
      | Ok response ->
          Alcotest.(check int)
            "^nai-97as larger bound decodes" 1
            (List.length response.embeddings)
      | Error error -> Alcotest.failf "larger bound: %s" (Ox_ai.Error.to_string error));
      (* One attempt means one request, and the 429's Retry-After is kept. *)
      let throttled headers =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.ok ~status:429 ~reason:"Too Many Requests" ~headers "slow"
          @ Fake_server.ok ~status:429 ~reason:"Too Many Requests" ~headers "slow")
      in
      let server = throttled [ ("Retry-After", "7") ] in
      (match embed ~max_attempts:1 server with
      | Error (`Unavailable { retry_after; retryable; status; _ }) ->
          Alcotest.(check (option int)) "^nai-8s4k typed status" (Some 429) status;
          Alcotest.(check bool) "^nai-rjkq retryable" true retryable;
          Alcotest.(check (option int))
            "^nai-rjkq delta-seconds" (Some 7000)
            (Option.map Ox.Duration.to_ms retry_after)
      | _ -> Alcotest.fail "expected Unavailable with Retry-After");
      Alcotest.(check int)
        "^nai-337c one attempt, one request" 1
        (Fake_server.connections server);
      let server = throttled [ ("Retry-After", "7") ] in
      (* ^safe-xls8 ^safe-s51t: default-budget refusal retains the throttling error. *)
      (match embed server with
      | Error (`Unavailable { status = Some 429; _ }) -> ()
      | _ -> Alcotest.fail "expected default-budget throttling error");
      Alcotest.(check int)
        "^safe-s51t default budget does not authorize replay" 1
        (Fake_server.connections server);
      (match
         embed ~max_attempts:1
           (throttled [ ("Retry-After", "Fri, 31 Dec 2099 23:59:59 GMT") ])
       with
      | Error (`Unavailable { retry_after = Some delay; _ }) ->
          Alcotest.(check bool)
            "^nai-rjkq HTTP-date in the future" true
            (Ox.Duration.to_ms delay > 0)
      | _ -> Alcotest.fail "expected an HTTP-date Retry-After");
      (match embed ~max_attempts:1 (throttled [ ("Retry-After", "soon") ]) with
      | Error (`Unavailable { retry_after = None; _ }) -> ()
      | _ -> Alcotest.fail "an invalid Retry-After must be None");
      (* ^nai-8s4k: the per-attempt timeout is the caller's, not a hidden 10 s. *)
      let slow =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw
          (Fake_server.after (Ox.Duration.seconds 2)
             (Fake_server.Response (Fake_server.http_response "{}")))
      in
      let started = Eio.Time.now env#clock in
      (match
         E.create ~http:(http ()) ~clock:env#clock ~logger ~api_key:key
           ~endpoint:(Fake_server.url slow "/embeddings")
           ~timeout:(Ox.Duration.ms 200) ~max_attempts:1 ~deadline
           E.{ model = "embedding-model"; input = Text "one"; dimensions = None }
       with
      | Error `Timeout ->
          Alcotest.(check bool)
            "^nai-8s4k attempt cut at the caller's timeout" true
            (Eio.Time.now env#clock -. started < 1.5)
      | _ -> Alcotest.fail "expected the attempt timeout");
      match embed ~max_attempts:1 (throttled []) with
      | Error (`Unavailable { retry_after = None; _ }) -> ()
      | _ -> Alcotest.fail "no header, no retry_after")

let test_failures () =
  Test_helpers.run (fun ~sw env ->
      let server ?(status = 200) body =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok ~status body)
      in
      let http () = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
      let logger = fst (Test_helpers.memory_logger env) in
      let responses server =
        R.create ~http:(http ()) ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/responses")
          ~deadline request
      in
      let embeddings server =
        E.create ~http:(http ()) ~clock:env#clock ~logger ~api_key:key
          ~endpoint:(Fake_server.url server "/embeddings")
          ~deadline
          E.{ model = "embedding-model"; input = Text "one"; dimensions = None }
      in
      let audio server =
        A.create ~http:(http ()) ~api_key:key
          ~endpoint:(Fake_server.url server "/audio/transcriptions")
          ~deadline
          A.
            {
              model = "audio-model";
              filename = "sample.wav";
              wav = Bytes.of_string "RIFF";
              language = None;
              prompt = None;
              temperature = None;
            }
      in
      check_authentication "Responses 401" (responses (server ~status:401 "denied"));
      check_authentication "embeddings 401" (embeddings (server ~status:401 "denied"));
      check_authentication "audio 401" (audio (server ~status:401 "denied"));
      check_input_too_large "audio 413" (audio (server ~status:413 "too large"));
      check_unavailable ~retryable:false "audio 500" (audio (server ~status:500 "boom"));
      check_invalid_response "embeddings malformed" (embeddings (server "not json")))

(* ^nor-pn0b: Pie's fixture — a completed reply that carries a [function_call] beside
   valid structured text — must be distinguishable from completed text-only, and its
   message text alone must never be delivered. *)

let pie_fixture =
  {|{"id":"r2","model":"audio-model","status":"completed","output":[{"type":"function_call","name":"lookup","call_id":"call_1","arguments":"{}"},{"type":"message","content":[{"text":"{\"text\":\"hello\"}"}]}]}|}

let refusal_fixture =
  {|{"id":"r3","model":"audio-model","status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"I cannot transcribe that"}]}]}|}

let test_response_kinds () =
  Test_helpers.run (fun ~sw env ->
      let create json =
        let server, http, logger = setup ~sw env json in
        ok
          (R.create ~http ~clock:env#clock ~logger ~api_key:key
             ~endpoint:(Fake_server.url server "/responses")
             ~deadline request)
      in
      let tool = create pie_fixture in
      check_outputs "Pie fixture kinds"
        [
          R.Function_call R.{ name = Some "lookup"; call_id = Some "call_1" };
          R.Output_text {|{"text":"hello"}|};
        ]
        tool;
      Alcotest.(check string) "Pie fixture text" {|{"text":"hello"}|} tool.R.text;
      check_refused "Pie fixture refused" "tool continuation lookup call_1"
        (R.deliverable tool);
      let refusal = create refusal_fixture in
      check_outputs "refusal kind" [ R.Refusal "I cannot transcribe that" ] refusal;
      check_refused "refusal refused" "refusal I cannot transcribe that"
        (R.deliverable refusal));
  (* The kinds and statuses a caller must refuse as well, decoded without a server. *)
  let decoded json =
    match R.decode (Yojson.Safe.from_string json) with
    | Ok response -> response
    | Error error -> Alcotest.failf "decode failed: %s" (Ox_ai.Error.to_string error)
  in
  let reasoning =
    decoded
      {|{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"hi"}]}]}|}
  in
  check_outputs "unmodelled item reported"
    [ R.Other "reasoning"; R.Output_text "hi" ]
    reasoning;
  check_delivered "reasoning does not disqualify ^oxpie-c8r5" "hi"
    (R.deliverable reasoning);
  let incomplete =
    decoded
      {|{"status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"hi"}]}]}|}
  in
  check_outputs "incomplete text reported" [ R.Output_text "hi" ] incomplete;
  check_refused "incomplete status refused" "not completed incomplete"
    (R.deliverable incomplete)

(* ^nor-474w: the caller's bound covers the whole encoded multipart body, and a body over
   it is refused with a typed error before any network I/O. *)

let audio_request : A.request =
  A.
    {
      model = "audio-model";
      filename = "sample.wav";
      wav = Bytes.make 3000 'R';
      language = Some "en";
      prompt = Some "medical";
      temperature = Some 0.;
    }

let check_over_bound what ~limit ~length = function
  | Error (`Input_too_large actual) ->
      Alcotest.(check int) (what ^ " limit") limit actual.Ox_json.limit;
      Alcotest.(check int) (what ^ " length") length actual.Ox_json.length
  | Error error -> Alcotest.failf "%s: %s" what (Ox_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let test_audio_bound () =
  Alcotest.(check int) "default unchanged" (8 * 1024 * 1024) A.max_request_bytes;
  let encoded = ok (A.body audio_request) in
  let length = Bytes.length encoded in
  Alcotest.(check bool)
    "the bound covers the multipart overhead" true
    (length > Bytes.length audio_request.A.wav);
  Alcotest.(check bool)
    "below the bound" true
    (Bytes.equal encoded (ok (A.body ~max_request_bytes:(length + 1) audio_request)));
  Alcotest.(check bool)
    "at the bound" true
    (Bytes.equal encoded (ok (A.body ~max_request_bytes:length audio_request)));
  check_over_bound "above the bound" ~limit:(length - 1) ~length
    (A.body ~max_request_bytes:(length - 1) audio_request);
  (match A.body ~max_request_bytes:0 audio_request with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.fail "a non-positive bound must be a defect");
  (match A.body ~max_request_bytes:(-1) audio_request with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.fail "a negative bound must be a defect");
  Test_helpers.run (fun ~sw env ->
      let server, http, _ = setup ~sw env {|{"text":"hello"}|} in
      let create ?max_request_bytes () =
        A.create ~http ~api_key:key ?max_request_bytes
          ~endpoint:(Fake_server.url server "/audio/transcriptions")
          ~deadline audio_request
      in
      check_over_bound "create over the bound" ~limit:(length - 1) ~length
        (create ~max_request_bytes:(length - 1) ());
      Alcotest.(check int)
        "refused before any connection" 0
        (Fake_server.connections server);
      Alcotest.(check string)
        "at the bound" "hello"
        (ok (create ~max_request_bytes:length ()));
      Alcotest.(check int)
        "the whole encoded body went over the wire" length
        (String.length (Fake_server.body server)))

(* One text frame as the client sends it, and one read back from the wire. *)
let frame_of_text text =
  Ox_http.Ws_codec.encode
    { Ox_http.Ws_codec.fin = true; opcode = Text; payload = Bytes.of_string text }

let read_frame input =
  let header = Eio.Buf_read.take 2 input in
  let length = Char.code header.[1] land 0x7f in
  let extended = if length = 126 then 2 else if length = 127 then 8 else 0 in
  let rest = Eio.Buf_read.take (extended + 4 + length) input in
  match Ox_http.Ws_codec.decode ~masked:true (Bytes.of_string (header ^ rest)) with
  | Ok (frame, _) -> frame
  | Error error ->
      Alcotest.failf "client frame: %s" (Ox_http.Ws_codec.parse_error_to_string error)

let test_realtime_session () =
  Test_helpers.run (fun ~sw env ->
      let listener =
        Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let port =
        match Eio.Net.listening_addr listener with
        | `Tcp (_, port) -> port
        | _ ->
            Alcotest.fail "expected TCP listening address in ai/test_openrouter fixture"
      in
      ignore
        (Eio.Fiber.fork_daemon ~sw (fun () ->
             let flow, _ = Eio.Net.accept ~sw listener in
             let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
             ignore (Eio.Buf_read.line input);
             let rec headers acc =
               let line = Eio.Buf_read.line input in
               if line = "" then acc
               else
                 let sep = String.index line ':' in
                 headers
                   (( String.lowercase_ascii (String.sub line 0 sep),
                      String.trim
                        (String.sub line (sep + 1) (String.length line - sep - 1)) )
                   :: acc)
             in
             let headers = headers [] in
             Alcotest.(check string)
               "auth" "Bearer fake-key"
               (match List.assoc_opt "authorization" headers with
               | Some value -> value
               | None ->
                   Alcotest.fail "missing ai/test_openrouter fixture: field authorization");
             Alcotest.(check string)
               "originator" "codex_cli_rs"
               (match List.assoc_opt "originator" headers with
               | Some value -> value
               | None ->
                   Alcotest.fail "missing ai/test_openrouter fixture: field originator");
             Alcotest.(check string)
               "subprotocol" "realtime"
               (match List.assoc_opt "sec-websocket-protocol" headers with
               | Some value -> value
               | None ->
                   Alcotest.fail
                     "missing ai/test_openrouter fixture: field sec-websocket-protocol");
             let accept =
               Ox_http.Ws_codec.accept_key ~sha1:Ox_http.Ox_http_tls_openssl.sha1
                 (match List.assoc_opt "sec-websocket-key" headers with
                 | Some value -> value
                 | None ->
                     Alcotest.fail
                       "missing ai/test_openrouter fixture: field sec-websocket-key")
             in
             Eio.Flow.copy_string
               ("HTTP/1.1 101 Switching Protocols\r\n\
                 Upgrade: websocket\r\n\
                 Connection: Upgrade\r\n\
                 Sec-WebSocket-Accept: " ^ accept
              ^ "\r\nSec-WebSocket-Protocol: realtime\r\n\r\n")
               flow;
             Eio.Flow.copy_string
               (Bytes.to_string (frame_of_text {|{"type":"conversation.item.created"}|}))
               flow;
             let frame = read_frame input in
             Alcotest.(check bool)
               "client frame is text" true
               (frame.Ox_http.Ws_codec.opcode = Ox_http.Ws_codec.Text);
             Alcotest.(check string)
               "client event" {|{"type":"input_audio_buffer.commit"}|}
               (Bytes.to_string frame.Ox_http.Ws_codec.payload);
             Eio.Flow.copy_string
               (Bytes.to_string
                  (frame_of_text {|{"type":"input_audio_buffer.committed"}|}))
               flow;
             `Stop_daemon));
      let url = Printf.sprintf "ws://127.0.0.1:%d/v1/realtime?model=test" port in
      let session =
        match
          Ox_ai_realtime.Session.connect ~sw ~net:env#net ~clock:env#clock ~api_key:key
            ~headers:[ ("originator", "codex_cli_rs") ]
            ~protocols:[ "realtime" ] url
        with
        | Ok session -> session
        | Error _ -> Alcotest.fail "upgrade failed"
      in
      let receive () =
        match Ox_ai_realtime.Session.receive session with
        | Ok event -> event
        | Error _ -> Alcotest.fail "missing event"
      in
      let event = receive () in
      Alcotest.(check string) "kind" "conversation.item.created" event.kind;
      (match
         Ox_ai_realtime.Session.send session
           (`Assoc [ ("type", `String "input_audio_buffer.commit") ])
       with
      | Ok () -> ()
      | Error _ -> Alcotest.fail "send failed");
      let event = receive () in
      Alcotest.(check string) "ack" "input_audio_buffer.committed" event.kind;
      match Ox_ai_realtime.Session.close session with
      | Ok () -> ()
      | Error _ -> Alcotest.fail "close failed")

let live_smoke ~(caps : < Ox_caps.Cap.env ; .. >) () =
  let key =
    match Ox_caps.Cap_sys.getenv_opt ~caps "OPENROUTER_API_KEY" with
    | Some key when String.trim key <> "" -> Ox_observability.Redact.make key
    | _ -> Alcotest.fail "OPENROUTER_API_KEY is required for opt-in smoke"
  in
  Test_helpers.run (fun ~sw env ->
      let http = Ox_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
      let logger = fst (Test_helpers.memory_logger env) in
      let model =
        Option.value ~default:"qwen/qwen3-embedding-4b"
          (Ox_caps.Cap_sys.getenv_opt ~caps "OX_AI_LIVE_EMBEDDING_MODEL")
      in
      let result =
        E.create ~http ~clock:env#clock ~logger ~api_key:key
          ~deadline:(Ox.Duration.seconds 30)
          E.{ model; input = Text "smoke"; dimensions = None }
      in
      ignore (ok result))

let main ~(caps : < Ox_caps.Cap.env ; .. >) () =
  let live =
    if Ox_caps.Cap_sys.getenv_opt ~caps "OX_AI_LIVE_SMOKE" = Some "1" then
      [
        ( "live",
          [ Alcotest.test_case "opt-in embedding ^air2-tst5" `Quick (live_smoke ~caps) ]
        );
      ]
    else []
  in
  Alcotest.run "AI OpenRouter"
    ([
       ( "offline",
         [
           Alcotest.test_case "Responses WAV wire ^air2-rsp1 ^nor-pn0b" `Quick
             test_responses;
           Alcotest.test_case "^nai-97as ^nai-337c ^nai-rjkq transport controls" `Quick
             test_transport_controls;
           Alcotest.test_case "embeddings index ^air2-emb2" `Quick test_embeddings;
           Alcotest.test_case "strict and Realtime events ^air2-rtm4" `Quick
             test_fail_closed;
           Alcotest.test_case "audio multipart ^air2-aud3" `Quick test_audio;
           Alcotest.test_case "failure matrix ^air2-tst5" `Quick test_failures;
           Alcotest.test_case "Responses output kinds ^nor-pn0b" `Quick
             test_response_kinds;
           Alcotest.test_case "audio request bound ^nor-474w" `Quick test_audio_bound;
           Alcotest.test_case "Codex WS exchange ^air2-rtm4" `Quick test_realtime_session;
         ] );
     ]
    @ live)

let () = main ~caps:(Ox_test.powerbox () :> < Ox_caps.Cap.env >) ()
