(* ^air2-rsp1 ^air2-emb2 ^air2-aud3 ^air2-rtm4 ^air2-tst5 *)
module R = Eta_ai_openrouter.Responses
module E = Eta_ai_openrouter.Embeddings
module A = Eta_ai_openrouter.Audio

let key = Eta_observability.Redact.make "fake-key"
let deadline = Eta.Duration.seconds 3

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
  let http = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
  let logger = fst (Test_helpers.memory_logger env) in
  (server, http, logger)

let ok = Test_helpers.expect_ok

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
      let sent = Test_helpers.jbody server in
      let contents =
        Test_helpers.(
          list_of (member "content" (List.hd (list_of (member "input" sent)))))
      in
      let audio = Test_helpers.member "input_audio" (List.nth contents 1) in
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
  (match Eta_ai_realtime.Session.decode {|{"type":"conversation.item.created"}|} with
  | Ok event ->
      Alcotest.(check string) "event type" "conversation.item.created" event.kind
  | Error _ -> Alcotest.fail "valid event rejected");
  match Eta_ai_realtime.Session.decode {|{"other":"missing"}|} with
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
      let _, headers, body = Option.get (Fake_server.request server) in
      Alcotest.(check bool)
        "multipart header" true
        (Test_helpers.contains (List.assoc "content-type" headers) "multipart/form-data");
      Alcotest.(check bool) "wav bytes" true (Test_helpers.contains body "RIFF");
      Alcotest.(check bool) "prompt" true (Test_helpers.contains body "medical"))

(* Every endpoint maps what a local server can answer: 401 is Authentication, the
   provider's over-size refusal is Input_too_large, a 5xx is Unavailable, and a 2xx body
   that is not the documented JSON is Invalid_response. ^air2-tst5 *)

let check_authentication what = function
  | Error (`Authentication _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Eta_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_input_too_large what = function
  | Error (`Input_too_large _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Eta_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_invalid_response what = function
  | Error (`Invalid_response _) -> ()
  | Error error -> Alcotest.failf "%s: %s" what (Eta_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let check_unavailable ~retryable what (result : ('a, Eta_ai.Error.t) result) =
  match result with
  | Error (`Unavailable { retryable = actual; _ }) ->
      Alcotest.(check bool) (what ^ " retryable") retryable actual
  | Error error -> Alcotest.failf "%s: %s" what (Eta_ai.Error.to_string error)
  | Ok _ -> Alcotest.failf "%s accepted" what

let test_failures () =
  Test_helpers.run (fun ~sw env ->
      let server ?(status = 200) body =
        Fake_server.serve ~net:env#net ~clock:env#clock ~sw (Fake_server.ok ~status body)
      in
      let http () = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
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

(* One text frame as the client sends it, and one read back from the wire. *)
let frame_of_text text =
  Eta_http.Ws_codec.encode
    { Eta_http.Ws_codec.fin = true; opcode = Text; payload = Bytes.of_string text }

let read_frame input =
  let header = Eio.Buf_read.take 2 input in
  let length = Char.code header.[1] land 0x7f in
  let extended = if length = 126 then 2 else if length = 127 then 8 else 0 in
  let rest = Eio.Buf_read.take (extended + 4 + length) input in
  match Eta_http.Ws_codec.decode ~masked:true (Bytes.of_string (header ^ rest)) with
  | Ok (frame, _) -> frame
  | Error error ->
      Alcotest.failf "client frame: %s" (Eta_http.Ws_codec.parse_error_to_string error)

let test_realtime_session () =
  Test_helpers.run (fun ~sw env ->
      let listener =
        Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let port =
        match Eio.Net.listening_addr listener with
        | `Tcp (_, port) -> port
        | _ -> assert false
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
               (List.assoc "authorization" headers);
             Alcotest.(check string)
               "originator" "codex_cli_rs"
               (List.assoc "originator" headers);
             Alcotest.(check string)
               "subprotocol" "realtime"
               (List.assoc "sec-websocket-protocol" headers);
             let accept =
               Eta_http.Ws_codec.accept_key ~sha1:Eta_http.Eta_http_tls_openssl.sha1
                 (List.assoc "sec-websocket-key" headers)
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
               (frame.Eta_http.Ws_codec.opcode = Eta_http.Ws_codec.Text);
             Alcotest.(check string)
               "client event" {|{"type":"input_audio_buffer.commit"}|}
               (Bytes.to_string frame.Eta_http.Ws_codec.payload);
             Eio.Flow.copy_string
               (Bytes.to_string
                  (frame_of_text {|{"type":"input_audio_buffer.committed"}|}))
               flow;
             `Stop_daemon));
      let url = Printf.sprintf "ws://127.0.0.1:%d/v1/realtime?model=test" port in
      let session =
        match
          Eta_ai_realtime.Session.connect ~sw ~net:env#net ~clock:env#clock ~api_key:key
            ~headers:[ ("originator", "codex_cli_rs") ]
            ~protocols:[ "realtime" ] url
        with
        | Ok session -> session
        | Error _ -> Alcotest.fail "upgrade failed"
      in
      let receive () =
        match Eta_ai_realtime.Session.receive session with
        | Ok event -> event
        | Error _ -> Alcotest.fail "missing event"
      in
      let event = receive () in
      Alcotest.(check string) "kind" "conversation.item.created" event.kind;
      (match
         Eta_ai_realtime.Session.send session
           (`Assoc [ ("type", `String "input_audio_buffer.commit") ])
       with
      | Ok () -> ()
      | Error _ -> Alcotest.fail "send failed");
      let event = receive () in
      Alcotest.(check string) "ack" "input_audio_buffer.committed" event.kind;
      match Eta_ai_realtime.Session.close session with
      | Ok () -> ()
      | Error _ -> Alcotest.fail "close failed")

let live_smoke () =
  let key =
    match Sys.getenv_opt "OPENROUTER_API_KEY" with
    | Some key when String.trim key <> "" -> Eta_observability.Redact.make key
    | _ -> Alcotest.fail "OPENROUTER_API_KEY is required for opt-in smoke"
  in
  Test_helpers.run (fun ~sw env ->
      let http = Eta_http.Client.create ~sw ~net:env#net ~clock:env#clock () in
      let logger = fst (Test_helpers.memory_logger env) in
      let model =
        Option.value ~default:"qwen/qwen3-embedding-4b"
          (Sys.getenv_opt "ETA_AI_LIVE_EMBEDDING_MODEL")
      in
      let result =
        E.create ~http ~clock:env#clock ~logger ~api_key:key
          ~deadline:(Eta.Duration.seconds 30)
          E.{ model; input = Text "smoke"; dimensions = None }
      in
      ignore (ok result))

let () =
  let live =
    if Sys.getenv_opt "ETA_AI_LIVE_SMOKE" = Some "1" then
      [ ("live", [ Alcotest.test_case "opt-in embedding ^air2-tst5" `Quick live_smoke ]) ]
    else []
  in
  Alcotest.run "AI OpenRouter"
    ([
       ( "offline",
         [
           Alcotest.test_case "Responses WAV wire ^air2-rsp1" `Quick test_responses;
           Alcotest.test_case "embeddings index ^air2-emb2" `Quick test_embeddings;
           Alcotest.test_case "strict and Realtime events ^air2-rtm4" `Quick
             test_fail_closed;
           Alcotest.test_case "audio multipart ^air2-aud3" `Quick test_audio;
           Alcotest.test_case "failure matrix ^air2-tst5" `Quick test_failures;
           Alcotest.test_case "Codex WS exchange ^air2-rtm4" `Quick test_realtime_session;
         ] );
     ]
    @ live)
