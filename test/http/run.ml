(* nhttp-6c3d: these tests compile with ox_http, Eio, and its public
   Cstruct buffer API; the native OpenSSL binding is linked by ox_http. *)
module H = Ox_http

let local = Eio.Net.Ipaddr.V4.loopback

let test_url () =
  Test_url.test_url_rejects_invalid_reg_name_hosts ();
  Test_url.test_url_rejects_invalid_path_query_percent_encoding ();
  Test_url.test_url_rejects_invalid_ip_literals ();
  Test_url.test_url_accepts_valid_ip_literals ()

let read_request flow =
  let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
  let rec headers () = if Eio.Buf_read.line input <> "" then headers () in
  headers ()

let with_server ?(tls = false) serve test =
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
                      if tls then
                        let ctx =
                          H.Ox_http_tls_openssl.create_server_ctx
                            ~certificate_chain_file:"localhost.crt"
                            ~private_key_file:"localhost.key"
                            ~alpn_protocols:[ "http/1.1" ] ()
                        in
                        (H.Tls_flow.create
                           ~raw:(raw :> H.Tls_flow.ty Eio.Resource.t)
                           ~ssl:(H.Ox_http_tls_openssl.create_server_ssl ctx)
                          :> Eio.Flow.two_way_ty Eio.Resource.t)
                      else (raw :> Eio.Flow.two_way_ty Eio.Resource.t)
                    in
                    serve env flow
                  with
                  | Eio.Io _ | End_of_file -> ()
                  | exn when Option.is_some (H.Tls_flow.failure_message exn) -> ()));
          let client =
            H.Client.create ~sw ~net:env#net ~clock:env#clock
              ~tls:(H.Client.tls ~ca_file:"localhost.crt" ())
              ()
          in
          let url =
            Printf.sprintf "%s://localhost:%d/answer"
              (if tls then "https" else "http")
              port
          in
          test env client url))

let good_response = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"
let expect_ok = function Ok x -> x | Error _ -> Alcotest.fail "HTTP request failed"

let read_body = function
  | `Read bytes -> Bytes.to_string bytes
  | `Skipped -> Alcotest.fail "body skipped"

let plaintext () =
  (* nhttp-irnw nhttp-0qob nhttp-jdb0 *)
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string
        "HTTP/1.1 302 Found\r\nLocation: /next\r\nContent-Length: 5\r\n\r\nhello" flow)
    (fun _ client url ->
      let response =
        H.Client.request client ~method_:"POST" ~url ~body:(Bytes.of_string "body") ()
        |> expect_ok
      in
      Alcotest.(check int) "redirect returned unchanged" 302 response.status;
      Alcotest.(check string) "body" "hello" (read_body response.body))

let tls_trust () =
  (* nhttp-gcka nhttp-5nqk nhttp-j0bc *)
  with_server ~tls:true
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string good_response flow)
    (fun _ client url ->
      let response = H.Client.request client ~method_:"GET" ~url () |> expect_ok in
      Alcotest.(check string) "TLS body" "hello" (read_body response.body))

let tls_untrusted () =
  with_server ~tls:true
    (fun _ flow ->
      (* ^nlintc-du4v: rejection may close TLS, but server cancellation must propagate. *)
      try read_request flow with
      | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
      | _ -> ())
    (fun env _client url ->
      Eio.Switch.run (fun sw ->
          let client = H.Client.create ~sw ~net:env#net ~clock:env#clock () in
          match H.Client.request client ~method_:"GET" ~url () with
          | Error (`Tls _) -> ()
          | _ -> Alcotest.fail "untrusted cert was not rejected"))

let oversized () =
  (* nhttp-xj7z *)
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabcdef" flow)
    (fun _ client url ->
      match H.Client.request client ~method_:"GET" ~url ~max_body_bytes:5 () with
      | Error (`Body { reason = `Too_large; _ }) -> ()
      | _ -> Alcotest.fail "oversized body was not rejected")

let chunked () =
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
        flow)
    (fun _ client url ->
      let response = H.Client.request client ~method_:"GET" ~url () |> expect_ok in
      Alcotest.(check string) "chunked decoded" "hello" (read_body response.body))

let idle_timeout () =
  (* nhttp-hmrw *)
  with_server
    (fun env flow ->
      read_request flow;
      Eio.Time.sleep env#clock 0.15;
      Eio.Flow.copy_string good_response flow)
    (fun _ client url ->
      match
        H.Client.request client ~method_:"GET" ~url ~response_idle:(Ox.Duration.ms 30) ()
      with
      | Error `Idle_timeout -> ()
      | _ -> Alcotest.fail "idle timeout not returned")

let deadline () =
  with_server
    (fun env flow ->
      read_request flow;
      Eio.Time.sleep env#clock 0.15;
      Eio.Flow.copy_string good_response flow)
    (fun _ client url ->
      match
        H.Client.request client ~method_:"GET" ~url ~deadline:(Ox.Duration.ms 30) ()
      with
      | Error `Timeout -> ()
      | _ -> Alcotest.fail "request deadline not returned")

let connection_failure () =
  (* nhttp-ed7t: refused TCP connections return a typed failure. *)
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let client = H.Client.create ~sw ~net:env#net ~clock:env#clock () in
          let port =
            Eio.Switch.run (fun listener_sw ->
                let listener =
                  Eio.Net.listen ~sw:listener_sw ~backlog:2 env#net (`Tcp (local, 0))
                in
                match Eio.Net.listening_addr listener with
                | `Tcp (_, port) -> port
                | _ -> assert false)
          in
          let url = Printf.sprintf "http://127.0.0.1:%d/" port in
          match H.Client.request client ~method_:"GET" ~url () with
          | Error (`Connect _) -> ()
          | _ -> Alcotest.fail "failed connect not typed"))

let malformed () =
  (* nhttp-ed7t: peer protocol errors are typed. *)
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string "THIS IS NOT HTTP\r\n\r\n" flow)
    (fun _ client url ->
      match H.Client.request client ~method_:"GET" ~url () with
      | Error (`Protocol _) -> ()
      | _ -> Alcotest.fail "malformed status not typed")

let closed () =
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string "HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nshort" flow)
    (fun _ client url ->
      match H.Client.request client ~method_:"GET" ~url () with
      | Error (`Body { status = 200; reason = `Truncated; _ }) -> ()
      | _ -> Alcotest.fail "truncated body not typed")

let slow_progress () =
  (* nhttp-hmrw: arriving bytes reset the response-idle timeout. *)
  with_server
    (fun env flow ->
      read_request flow;
      String.iter
        (fun c ->
          Eio.Flow.copy_string (String.make 1 c) flow;
          Eio.Time.sleep env#clock 0.008)
        good_response)
    (fun _ client url ->
      let response =
        H.Client.request client ~method_:"GET" ~url ~response_idle:(Ox.Duration.ms 35) ()
        |> expect_ok
      in
      Alcotest.(check string) "progressing response" "hello" (read_body response.body))

let cancel () =
  (* nhttp-6a47: cancellation interrupts the request and closes its socket. *)
  let saw_close = ref false in
  with_server
    (fun _ flow ->
      read_request flow;
      let b = Cstruct.create 1 in
      try ignore (Eio.Flow.single_read flow b) with End_of_file -> saw_close := true)
    (fun env client url ->
      let winner =
        Eio.Fiber.first
          (fun () ->
            ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: A normal reply loses this cancellation probe; the winner and peer socket-close assertions decide the outcome. *)
             let _request_result = H.Client.request client ~method_:"GET" ~url () in
             ());
            false)
          (fun () ->
            Eio.Time.sleep env#clock 0.03;
            true)
      in
      Alcotest.(check bool) "cancel wins" true winner);
  Alcotest.(check bool) "server observed socket close" true !saw_close

let close_delimited () =
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string "HTTP/1.0 200 OK\r\n\r\nhello" flow)
    (fun _ client url ->
      let response = H.Client.request client ~method_:"GET" ~url () |> expect_ok in
      Alcotest.(check string) "EOF framed" "hello" (read_body response.body))

let tls_wrong_identity () =
  with_server ~tls:true
    (fun _ flow ->
      (* ^nlintc-du4v: rejection may close TLS, but server cancellation must propagate. *)
      try read_request flow with
      | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
      | _ -> ())
    (fun _ client url ->
      let needle = "localhost" in
      let start =
        match String.index_opt url '/' with
        | None -> assert false
        | Some _ -> String.length "https://"
      in
      let wrong =
        String.sub url 0 start ^ "127.0.0.1"
        ^ String.sub url
            (start + String.length needle)
            (String.length url - start - String.length needle)
      in
      match H.Client.request client ~method_:"GET" ~url:wrong () with
      | Error (`Tls _) -> ()
      | _ -> Alcotest.fail "wrong certificate host was not rejected")

let tls_handshake_deadline () =
  (* nhttp-hmrw: the request deadline includes the TLS handshake. *)
  with_server
    (fun env _flow -> Eio.Time.sleep env#clock 0.12)
    (fun _ client url ->
      let secure = "https" ^ String.sub url 4 (String.length url - 4) in
      match
        H.Client.request client ~method_:"GET" ~url:secure ~deadline:(Ox.Duration.ms 30)
          ()
      with
      | Error `Timeout -> ()
      | _ -> Alcotest.fail "TLS handshake escaped overall deadline")

let chunked_overflow () =
  (* nhttp-xj7z: chunk framing cannot bypass the configured body limit. *)
  with_server
    (fun _ flow ->
      read_request flow;
      Eio.Flow.copy_string
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6\r\nabcdef\r\n0\r\n\r\n"
        flow)
    (fun _ client url ->
      match H.Client.request client ~method_:"GET" ~url ~max_body_bytes:5 () with
      | Error (`Body { reason = `Too_large; _ }) -> ()
      | _ -> Alcotest.fail "chunked oversized body was not rejected")

let smoke ~(caps : < Ox_caps.Cap.env ; .. >) () =
  if Ox_caps.Cap_sys.getenv_opt ~caps "OX_HTTP_LIVE_SMOKE" = Some "1" then
    Eio_main.run (fun env ->
        Eio.Switch.run (fun sw ->
            let client = H.Client.create ~sw ~net:env#net ~clock:env#clock () in
            match
              H.Client.request client ~method_:"GET" ~url:"https://example.com/"
                ~deadline:(Ox.Duration.seconds 10) ()
            with
            | Ok response ->
                Alcotest.(check bool) "remote status" true (response.status >= 200)
            | Error _ -> Alcotest.fail "live HTTP smoke failed"))

let () =
  let caps = (Ox_test.powerbox () :> < Ox_caps.Cap.env >) in
  Alcotest.run "HTTP client"
    [
      ( "copied codecs",
        [
          Alcotest.test_case "URL validation" `Quick test_url;
          Alcotest.test_case "writer rejects injection" `Quick
            Test_writer_legacy.test_reject_header_injection;
          Alcotest.test_case "writer fixed body" `Quick
            Test_writer_legacy.test_fixed_request;
          Alcotest.test_case "writer framing" `Quick
            Test_writer_legacy.test_invalid_framing;
          Alcotest.test_case "response parser" `Quick
            Test_writer_legacy.test_parse_response;
          Alcotest.test_case "invalid content length" `Quick
            Test_writer_legacy.test_parse_cl_rejection;
        ] );
      ("TLS flow close (nhttp-7pp8 nhttp-rs5p)", Test_tls_flow.cases);
      ( "copied OpenSSL binding",
        [
          Alcotest.test_case "handle ordering" `Quick
            Test_openssl_compare.test_ctx_ssl_handle_ordering;
          Alcotest.test_case "buffer bounds" `Quick
            Test_openssl_bounds.test_invalid_slices_prehandshake;
          Alcotest.test_case "zero-length slice" `Quick
            Test_openssl_bounds.test_zero_length_end_slice_valid;
          Alcotest.test_case "pending BIO bounds" `Quick
            Test_openssl_bounds.test_invalid_slices_pending_bio;
        ] );
      ("final heads and disposition", Test_client_heads.cases);
      ( "transport",
        [
          Alcotest.test_case "plaintext redirect POST" `Quick plaintext;
          Alcotest.test_case "trusted TLS" `Quick tls_trust;
          Alcotest.test_case "untrusted TLS" `Quick tls_untrusted;
          Alcotest.test_case "body limit" `Quick oversized;
          Alcotest.test_case "chunked" `Quick chunked;
          Alcotest.test_case "idle" `Quick idle_timeout;
          Alcotest.test_case "deadline" `Quick deadline;
          Alcotest.test_case "slow progress" `Quick slow_progress;
          Alcotest.test_case "malformed HTTP" `Quick malformed;
          Alcotest.test_case "refused connect" `Quick connection_failure;
          Alcotest.test_case "truncated body" `Quick closed;
          Alcotest.test_case "EOF framed" `Quick close_delimited;
          Alcotest.test_case "wrong TLS identity" `Quick tls_wrong_identity;
          Alcotest.test_case "cancel closes socket" `Quick cancel;
          Alcotest.test_case "TLS handshake deadline" `Quick tls_handshake_deadline;
          Alcotest.test_case "chunked body limit" `Quick chunked_overflow;
          Alcotest.test_case "opt-in live smoke" `Quick (smoke ~caps);
        ] );
    ]
