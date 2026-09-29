module H = Ox_http
module C = H.Ws_codec
module W = H.Ws_client

let local = Eio.Net.Ipaddr.V4.loopback

let expect_ok = function
  | Ok v -> v
  | Error e ->
      Alcotest.fail
        ("WebSocket operation unexpectedly failed: "
        ^
        match e with
        | `Url x | `Connect x | `Tls x | `Protocol x -> x
        | `Upgrade_failed (code, _) -> "upgrade " ^ string_of_int code
        | `Closed (code, x) -> "closed " ^ string_of_int code ^ ": " ^ x
        | `Timeout -> "timeout"
        | `Message_too_large -> "message too large")

let serve ?(tls = false) ?(observe_tls = fun _ -> ()) server test =
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener = Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (local, 0)) in
          let port =
            match Eio.Net.listening_addr listener with
            | `Tcp (_, port) -> port
            | _ -> assert false
          in
          Eio.Fiber.fork ~sw (fun () ->
              Eio.Switch.run (fun server_sw ->
                  let raw, _ = Eio.Net.accept ~sw:server_sw listener in
                  try
                    let flow : Eio.Flow.two_way_ty Eio.Resource.t =
                      if not tls then (raw :> Eio.Flow.two_way_ty Eio.Resource.t)
                      else
                        let ctx =
                          H.Ox_http_tls_openssl.create_server_ctx
                            ~certificate_chain_file:"../localhost.crt"
                            ~private_key_file:"../localhost.key"
                            ~alpn_protocols:[ "http/1.1" ] ()
                        in
                        let ssl = H.Ox_http_tls_openssl.create_server_ssl ctx in
                        let flow =
                          H.Tls_flow.create
                            ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t)
                            ~ssl
                        in
                        observe_tls ssl;
                        (flow :> Eio.Flow.two_way_ty Eio.Resource.t)
                    in
                    server env flow
                  with Eio.Io _ | End_of_file | H.Tls_flow.Tls_failure _ -> ()));
          let url =
            Printf.sprintf "%s://localhost:%d/realtime?model=test"
              (if tls then "wss" else "ws")
              port
          in
          test env sw url))

let request flow =
  let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
  let line = Eio.Buf_read.line input in
  let rec headers acc =
    let line = Eio.Buf_read.line input in
    if line = "" then List.rev acc
    else
      let colon = String.index line ':' in
      headers
        (( String.lowercase_ascii (String.sub line 0 colon),
           String.trim (String.sub line (colon + 1) (String.length line - colon - 1)) )
        :: acc)
  in
  (line, headers [], input)

let header key headers = List.assoc key headers

let upgrade ?(status = 101) ?(accept = true) flow headers =
  let value =
    if accept then
      C.accept_key ~sha1:H.Ox_http_tls_openssl.sha1 (header "sec-websocket-key" headers)
    else "invalid"
  in
  Eio.Flow.copy_string
    (Printf.sprintf
       "HTTP/1.1 %d reply\r\n\
        Upgrade: websocket\r\n\
        Connection: Upgrade\r\n\
        Sec-WebSocket-Accept: %s\r\n\
        \r\n"
       status value)
    flow

let frame op text =
  C.encode { C.fin = true; opcode = op; payload = Bytes.of_string text }
  |> Bytes.to_string

let test_plain () =
  (* ^nws-a7k2 ^nws-c3m8 ^nws-e6t9: upgrade, auth, binary, ping, close, masking. *)
  serve
    (fun _ flow ->
      let line, headers, input = request flow in
      Alcotest.(check string) "request target" "GET /realtime?model=test HTTP/1.1" line;
      Alcotest.(check string) "auth" "Bearer local" (header "authorization" headers);
      upgrade flow headers;
      Eio.Flow.copy_string
        (frame C.Ping "hi" ^ frame C.Text "event" ^ frame C.Binary "audio")
        flow;
      let masked = Eio.Buf_read.take 2 input in
      Alcotest.(check bool)
        "client frame masked" true
        (Char.code masked.[1] land 0x80 <> 0);
      let n = Char.code masked.[1] land 0x7f in
      let rest = Eio.Buf_read.take (4 + n) input in
      (match C.decode ~masked:true (Bytes.of_string (masked ^ rest)) with
      | Ok ({ opcode = C.Pong; payload; _ }, _) ->
          Alcotest.(check string) "pong" "hi" (Bytes.to_string payload)
      | _ -> Alcotest.fail "expected pong");
      let masked = Eio.Buf_read.take 2 input in
      let n = Char.code masked.[1] land 0x7f in
      let rest = Eio.Buf_read.take (4 + n) input in
      (match C.decode ~masked:true (Bytes.of_string (masked ^ rest)) with
      | Ok ({ opcode = C.Text; payload; _ }, _) ->
          Alcotest.(check string) "client text" "reply" (Bytes.to_string payload)
      | _ -> Alcotest.fail "expected masked client text");
      Eio.Flow.copy_string (frame C.Close "\003\232") flow)
    (fun env sw url ->
      let ws =
        W.connect ~sw ~net:env#net ~clock:env#clock
          ~headers:[ ("Authorization", "Bearer local") ]
          url
        |> expect_ok
      in
      (match W.receive ws with
      | Ok (`Text "event") -> ()
      | _ -> Alcotest.fail "missing text");
      W.send_text ws "reply" |> expect_ok;
      (match W.receive ws with
      | Ok (`Binary b) -> Alcotest.(check string) "audio" "audio" (Bytes.to_string b)
      | _ -> Alcotest.fail "missing binary");
      match W.receive ws with
      | Error (`Closed (1000, "")) -> ()
      | _ -> Alcotest.fail "missing close")

let test_tls () =
  (* ^nws-a7k2: same trust anchor and peer identity policy as HTTP client. *)
  serve ~tls:true
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      Eio.Flow.copy_string (frame C.Text "secure") flow)
    (fun env sw url ->
      let ws =
        W.connect ~sw ~net:env#net ~clock:env#clock ~ca_file:"../localhost.crt" url
        |> expect_ok
      in
      match W.receive ws with Ok (`Text "secure") -> () | _ -> Alcotest.fail "TLS event")

let test_tls_close () =
  (* nhttp-rs5p: public WebSocket close must close the TLS wrapper, not raw TCP. *)
  let peer_ssl = ref None in
  let notified = ref false in
  serve ~tls:true
    ~observe_tls:(fun ssl -> peer_ssl := Some ssl)
    (fun _ flow ->
      let _, headers, input = request flow in
      upgrade flow headers;
      let head = Eio.Buf_read.take 2 input in
      let length = Char.code head.[1] land 0x7f in
      let rest = Eio.Buf_read.take (4 + length) input in
      (match C.decode ~masked:true (Bytes.of_string (head ^ rest)) with
      | Ok ({ opcode = C.Close; _ }, _) -> ()
      | _ -> Alcotest.fail "expected WebSocket close");
      (try
         ignore (Eio.Buf_read.take 1 input);
         Alcotest.fail "expected TLS EOF"
       with End_of_file -> ());
      let ssl = Option.get !peer_ssl in
      match
        H.Ox_http_tls_openssl.read ssl (Cstruct.to_bigarray (Cstruct.create 1)) 0 1
      with
      | H.Ox_http_tls_openssl.Io_error { code = 6; _ } -> notified := true
      | _ -> Alcotest.fail "WebSocket close did not send TLS close_notify")
    (fun env sw url ->
      let ws =
        W.connect ~sw ~net:env#net ~clock:env#clock ~ca_file:"../localhost.crt" url
        |> expect_ok
      in
      W.close ws |> expect_ok;
      W.close ws |> expect_ok);
  Alcotest.(check bool) "TLS peer observed close_notify" true !notified

let test_tls_untrusted () =
  (* ^nws-b9q4: untrusted peer retains typed TLS diagnostic. *)
  serve ~tls:true
    (fun _ flow -> ignore (request flow))
    (fun env sw url ->
      match W.connect ~sw ~net:env#net ~clock:env#clock url with
      | Error (`Tls _) -> ()
      | _ -> Alcotest.fail "expected TLS verification error")

let test_reject () =
  (* ^nws-b9q4: non-101 retains status and headers. *)
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade ~status:401 flow headers)
    (fun env sw url ->
      match W.connect ~sw ~net:env#net ~clock:env#clock url with
      | Error (`Upgrade_failed (401, _)) -> ()
      | _ -> Alcotest.fail "expected 401 upgrade failure")

let test_bad_accept () =
  (* ^nws-b9q4: hostile handshake cannot establish. *)
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade ~accept:false flow headers)
    (fun env sw url ->
      match W.connect ~sw ~net:env#net ~clock:env#clock url with
      | Error (`Protocol _) -> ()
      | _ -> Alcotest.fail "expected invalid accept rejection")

let test_timeout () =
  (* ^nws-b9q4: timeout spans the response wait. *)
  serve
    (fun env flow ->
      ignore (request flow);
      Eio.Time.sleep env#clock 0.15)
    (fun env sw url ->
      match
        W.connect ~sw ~net:env#net ~clock:env#clock
          ~establishment_timeout:(Ox.Duration.ms 20) url
      with
      | Error `Timeout -> ()
      | _ -> Alcotest.fail "upgrade timeout expected")

let test_limit () =
  (* ^nws-e6t9: declared payload over limit rejected before allocation. *)
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      Eio.Flow.copy_string "\x82\x7f\x00\x00\x00\x00\x00\x10\x00\x00" flow)
    (fun env sw url ->
      let ws =
        W.connect ~sw ~net:env#net ~clock:env#clock ~max_message_bytes:32 url |> expect_ok
      in
      match W.receive ws with
      | Error `Message_too_large -> ()
      | _ -> Alcotest.fail "oversized payload accepted")

let test_fragmented () =
  (* ^nws-c3m8 ^nws-e6t9: fragmentation with interleaved ping remains ordered. *)
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      let part =
        C.encode { C.fin = false; opcode = Text; payload = Bytes.of_string "hel" }
        |> Bytes.to_string
      in
      Eio.Flow.copy_string (part ^ frame C.Ping "p" ^ frame C.Continuation "lo") flow)
    (fun env sw url ->
      let ws = W.connect ~sw ~net:env#net ~clock:env#clock url |> expect_ok in
      match W.receive ws with
      | Ok (`Text "hello") -> ()
      | _ -> Alcotest.fail "fragmented text lost")

let test_bad_utf8 () =
  (* ^nws-e6t9: invalid UTF-8 is a typed protocol failure. *)
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      Eio.Flow.copy_string (frame C.Text "\255") flow)
    (fun env sw url ->
      let ws = W.connect ~sw ~net:env#net ~clock:env#clock url |> expect_ok in
      match W.receive ws with
      | Error (`Protocol _) -> ()
      | _ -> Alcotest.fail "accepted invalid text")

let test_close_wakes_reader () =
  (* ^nws-e6t9: explicit close releases a concurrent blocked read. *)
  serve
    (fun env flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      Eio.Time.sleep env#clock 0.08)
    (fun env sw url ->
      let ws = W.connect ~sw ~net:env#net ~clock:env#clock url |> expect_ok in
      let done_, resolve = Eio.Promise.create () in
      Eio.Fiber.fork ~sw (fun () -> Eio.Promise.resolve resolve (W.receive ws));
      Eio.Fiber.yield ();
      W.close ws |> expect_ok;
      match Eio.Promise.await done_ with
      | Error (`Closed _) -> ()
      | _ -> Alcotest.fail "blocked read not released")

let test_switch_ownership () =
  (* ^nws-e6t9: releasing the caller's switch drops the established socket. *)
  let peer_closed = ref false in
  serve
    (fun _ flow ->
      let _, headers, _ = request flow in
      upgrade flow headers;
      try ignore (Eio.Flow.single_read flow (Cstruct.create 1))
      with End_of_file -> peer_closed := true)
    (fun env _ url ->
      Eio.Switch.run (fun session_sw ->
          ignore (W.connect ~sw:session_sw ~net:env#net ~clock:env#clock url |> expect_ok)));
  Alcotest.(check bool) "switch closed peer socket" true !peer_closed

let test_cancel_upgrade () =
  (* ^nws-b9q4 ^nws-e6t9: cancellation during upgrade closes the pending socket. *)
  let peer_closed = ref false in
  serve
    (fun _ flow ->
      ignore (request flow);
      try ignore (Eio.Flow.single_read flow (Cstruct.create 1))
      with End_of_file -> peer_closed := true)
    (fun env sw url ->
      let winner =
        Eio.Fiber.first
          (fun () ->
            ignore (W.connect ~sw ~net:env#net ~clock:env#clock url);
            false)
          (fun () ->
            Eio.Time.sleep env#clock 0.03;
            true)
      in
      Alcotest.(check bool) "cancel wins" true winner);
  Alcotest.(check bool) "cancel closed peer socket" true !peer_closed

let () =
  Alcotest.run "WebSocket client"
    [
      ("copied codec", Test_ws_codec.cases);
      ( "direct transport",
        [
          Alcotest.test_case "^nws-a7k2 ^nws-c3m8 plain flow" `Quick test_plain;
          Alcotest.test_case "^nws-a7k2 TLS flow" `Quick test_tls;
          Alcotest.test_case "^nhttp-rs5p TLS close_notify" `Quick test_tls_close;
          Alcotest.test_case "^nws-b9q4 untrusted TLS" `Quick test_tls_untrusted;
          Alcotest.test_case "^nws-b9q4 401 upgrade" `Quick test_reject;
          Alcotest.test_case "^nws-b9q4 invalid accept" `Quick test_bad_accept;
          Alcotest.test_case "^nws-b9q4 establishment timeout" `Quick test_timeout;
          Alcotest.test_case "^nws-e6t9 frame budget" `Quick test_limit;
          Alcotest.test_case "^nws-c3m8 fragmented frames" `Quick test_fragmented;
          Alcotest.test_case "^nws-e6t9 bad UTF-8" `Quick test_bad_utf8;
          Alcotest.test_case "^nws-e6t9 close wakes read" `Quick test_close_wakes_reader;
          Alcotest.test_case "^nws-e6t9 switch ownership" `Quick test_switch_ownership;
          Alcotest.test_case "^nws-b9q4 ^nws-e6t9 cancel upgrade" `Quick
            test_cancel_upgrade;
        ] );
    ]
