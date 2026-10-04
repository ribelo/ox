module C = Ox_http.Client
module Ssl = Ox_http.Ox_http_tls_openssl
module Tls = Ox_http.Tls_flow

let fail = Alcotest.fail
let check_headers expected actual =
  Alcotest.(check (list (pair string string))) "ordered final headers" expected actual

let read_request flow =
  let input = Eio.Buf_read.of_flow flow ~max_size:32768 in
  ignore (Eio.Buf_read.line input);
  let rec headers () = if Eio.Buf_read.line input <> "" then headers () in
  headers ()

let closed flow =
  match Eio.Flow.single_read flow (Cstruct.create 1) with
  | _ -> fail "client sent unexpected bytes instead of closing"
  | exception End_of_file -> ()
  | exception Eio.Io _ -> ()
  | exception exn when Option.is_some (Tls.failure_message exn) -> ()

(* Local plaintext/TLS peer; both fibers and every socket are switch-owned. *)
let with_server ?(tls = false) script test =
  Ox_test.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 5. (fun () ->
          Eio.Switch.run (fun sw ->
              let listener = Eio.Net.listen ~sw ~reuse_addr:true ~backlog:1 env#net
                  (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0)) in
              let port = match Eio.Net.listening_addr listener with
                | `Tcp (_, port) -> port | _ -> assert false in
              let url = Printf.sprintf "%s://localhost:%d/" (if tls then "https" else "http") port in
              let config = C.tls ~ca_file:"localhost.crt" () in
              let client = C.create ~sw ~net:env#net ~clock:env#clock ~tls:config () in
              let peer_closed, resolve_closed = Eio.Promise.create () in
              Eio.Fiber.both
                (fun () ->
                  let raw, _ = Eio.Net.accept ~sw listener in
                  let flow = if tls then (
                      let ctx = Ssl.create_server_ctx ~cert_file:"localhost.crt" ~key_file:"localhost.key" in
                      let ssl = Ssl.create_ssl ctx ~hostname:None ~ip:None ~alpn_protocols:[] in
                      Tls.create ~raw:(raw :> Tls.ty Eio.Resource.t) ~ssl)
                    else (raw :> Tls.ty Eio.Resource.t) in
                  Fun.protect ~finally:(fun () ->
                      try Eio.Resource.close flow with
                      | Eio.Io _ | End_of_file -> ()
                      | exn when Option.is_some (Tls.failure_message exn) -> ())
                    (fun () ->
                      read_request flow;
                      script flow raw;
                      Eio.Promise.resolve resolve_closed ()))
                (fun () -> test env sw client url peer_closed)))))

let provenance = [ ("X-Provenance", "first"); ("X-Provenance", "second") ]
let head status framing =
  Printf.sprintf "HTTP/1.1 %d Test\r\nX-Provenance: first\r\nX-Provenance: second\r\n%s\r\n" status framing

let expect_read status headers body = function
  | Ok { C.status = got; headers = got_headers; body = `Read bytes } ->
      Alcotest.(check int) "final status" status got;
      check_headers headers got_headers;
      Alcotest.(check string) "exact body" body (Bytes.to_string bytes)
  | _ -> fail "expected an acquired final body"

let expect_body status headers matches = function
  | Error (`Body failure) ->
      Alcotest.(check int) "known final status" status failure.status;
      check_headers headers failure.headers;
      if not (matches failure.reason) then fail "wrong post-head reason"
  | _ -> fail "body failure lost final head"

let bytes_failure ?(tls = false) ?(limit = 1048576) status framing body matches =
  let headers = provenance @ framing in
  let framing_wire = String.concat "" (List.map (fun (k, v) -> k ^ ": " ^ v ^ "\r\n") framing) in
  with_server ~tls
    (fun flow raw -> Eio.Flow.copy_string (head status framing_wire ^ body) flow; Eio.Resource.close raw)
    (fun _ _ client url done_ ->
      expect_body status headers matches (C.request client ~method_:"GET" ~url ~max_body_bytes:limit ());
      Eio.Promise.await done_)

let final_provenance () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-oaw6 *)
  List.iter (fun status ->
      bytes_failure status [ ("Content-Length", "6") ] "abc" ((=) `Truncated)) [ 401; 200 ];
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] "4\r\nab" ((=) `Truncated);
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] "nope\r\n"
    (function `Malformed _ -> true | _ -> false);
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] "2\r\nabX\r\n"
    (function `Malformed _ -> true | _ -> false)

let bounded_body () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-hpo2 ^nhttp-8ixg *)
  List.iter (fun status ->
      List.iter (fun (framing, body) ->
          bytes_failure ~limit:3 status framing body ((=) `Too_large))
        [ ([ ("Content-Length", "4") ], "");
          ([ ("Transfer-Encoding", "chunked") ], "4\r\n");
          ([], "four") ]) [ 401; 200 ];
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] "-1\r\n"
    (function `Malformed _ -> true | _ -> false)

let skip_matrix () =
  (* ^nhttp-uhrh ^nhttp-w60z ^nhttp-3bbt ^nhttp-w5yp ^nhttp-jxpd ^nhttp-ey81 ^nhttp-bx60 ^nhttp-8ixg *)
  List.iter (fun status ->
      List.iter (fun framing ->
          let calls = ref 0 in
          with_server
            (fun flow _ -> Eio.Flow.copy_string (head status framing) flow; closed flow)
            (fun _ _ client url done_ ->
              let expected = provenance @
                (if framing = "" then [] else if String.starts_with ~prefix:"Content" framing
                 then [ ("Content-Length", "999999999") ] else [ ("Transfer-Encoding", "nonsense") ]) in
              let on_head ~status:got ~headers =
                incr calls;
                Alcotest.(check int) "policy status" status got;
                check_headers expected headers;
                `Skip in
              (match C.request client ~method_:"GET" ~url ~max_body_bytes:0 ~on_head () with
              | Ok { status = got; headers; body = `Skipped } ->
                  Alcotest.(check int) "skipped status" status got; check_headers expected headers
              | _ -> fail "skip waited for or interpreted the body");
              Alcotest.(check int) "one policy call" 1 !calls;
              Eio.Promise.await done_))
        [ "Content-Length: 999999999\r\n"; "Transfer-Encoding: nonsense\r\n"; "" ])
    [ 200; 401; 429; 503; 302 ]

let default_read_and_empty () =
  (* ^nhttp-uhrh ^nhttp-3bbt ^nhttp-w5yp ^nhttp-jxpd ^nhttp-ey81 ^nhttp-8ixg *)
  List.iter (fun (method_, status, body) ->
      with_server
        (fun flow _ -> Eio.Flow.copy_string (head status "Content-Length: 3\r\n" ^ body) flow; closed flow)
        (fun _ _ client url done_ ->
          expect_read status (provenance @ [ ("Content-Length", "3") ]) body
            (C.request client ~method_ ~url ()); Eio.Promise.await done_))
    [ ("GET", 200, "abc"); ("GET", 401, "abc"); ("GET", 302, "abc");
      ("HEAD", 200, ""); ("GET", 204, ""); ("GET", 304, "") ];
  with_server
    (fun flow _ -> Eio.Flow.copy_string (head 200 "Content-Length: 0\r\n") flow; closed flow)
    (fun _ _ client url done_ ->
      expect_read 200 (provenance @ [ ("Content-Length", "0") ]) ""
        (C.request client ~method_:"GET" ~url ()); Eio.Promise.await done_)

let timeout_phase ~after_head ~idle =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-v147 ^nhttp-dgoe ^nhttp-hpo2 ^nhttp-32fq *)
  with_server
    (fun flow _ -> if after_head then Eio.Flow.copy_string (head 401 "Content-Length: 2\r\n") flow;
      closed flow)
    (fun _ _ client url done_ ->
      let delay = Ox.Duration.ms 30 in
      let result = C.request client ~method_:"GET" ~url
          ?deadline:(if idle then None else Some delay)
          ?response_idle:(if idle then Some delay else None) () in
      if after_head then expect_body 401 (provenance @ [ ("Content-Length", "2") ])
          ((=) (if idle then `Idle_timeout else `Timeout)) result
      else (match result with
          | Error `Timeout when not idle -> ()
          | Error `Idle_timeout when idle -> ()
          | _ -> fail "pre-head timeout acquired phantom provenance");
      Eio.Promise.await done_)

let cancellation ~after_head =
  (* ^nhttp-v147 ^nhttp-0d9e ^nhttp-32fq *)
  let arrived, resolve_arrived = Eio.Promise.create () in
  with_server
    (fun flow _ ->
      if after_head then Eio.Flow.copy_string (head 200 "Content-Length: 2\r\n") flow
      else Eio.Promise.resolve resolve_arrived ();
      closed flow)
    (fun _ _ client url done_ ->
      let propagated = ref false in
      Eio.Cancel.sub (fun cc ->
          Eio.Fiber.both
            (fun () -> Eio.Promise.await arrived; Eio.Cancel.cancel cc Exit)
            (fun () ->
              match C.request client ~method_:"GET" ~url
                  ~on_head:(fun ~status:_ ~headers:_ -> Eio.Promise.resolve resolve_arrived (); `Read) () with
              | _ -> fail "external cancellation became a result"
              | exception Eio.Cancel.Cancelled _ -> propagated := true));
      Alcotest.(check bool) "original cancellation propagated" true !propagated;
      Eio.Promise.await done_)

exception Policy_defect of int

let policy_exceptions () =
  (* ^nhttp-0d9e ^nhttp-32fq *)
  List.iter (fun original ->
      with_server
        (fun flow _ -> Eio.Flow.copy_string (head 200 "Content-Length: 100\r\n") flow; closed flow)
        (fun _ _ client url done_ ->
          let on_head ~status:_ ~headers:_ = raise original in
          (match C.request client ~method_:"GET" ~url ~on_head () with
          | _ -> fail "policy exception became typed HTTP error"
          | exception exn ->
              Alcotest.(check bool) "same exception object" true (exn == original);
              Alcotest.(check bool) "policy backtrace retained" true
                (String.length (Printexc.get_backtrace ()) > 0));
          Eio.Promise.await done_))
    [ Policy_defect 42; Failure "caller defect"; End_of_file;
      Eio.Io (Eio.Net.E (Eio.Net.Connection_failure Eio.Net.No_matching_addresses), []) ]

let informationals ?(tls = false) ~skip ~split () =
  (* ^nhttp-bx60 ^nhttp-8ixg ^nhttp-32fq *)
  let seen, resolve_seen = Eio.Promise.create () in
  let continue, resolve_continue = Eio.Promise.create () in
  let calls = ref 0 in
  let provisional = "HTTP/1.1 100 Continue\r\nX-Info: one\r\n\r\n" ^
      "HTTP/1.1 103 Early Hints\r\nLink: </one>\r\n\r\n" ^
      "HTTP/1.1 103 Early Hints\r\nLink: </two>\r\n\r\n" in
  let final = head 200 "Content-Length: 3\r\n" in
  with_server ~tls
    (fun flow _ ->
      if split then (
        Eio.Flow.copy_string (provisional ^ String.sub final 0 (String.length final - 1)) flow;
        Eio.Promise.resolve resolve_seen ();
        Eio.Promise.await continue;
        Eio.Flow.copy_string "\n" flow)
      else Eio.Flow.copy_string (provisional ^ final) flow;
      if not skip then Eio.Flow.copy_string "abc" flow;
      closed flow)
    (fun _ sw client url done_ ->
      if split then Eio.Fiber.fork ~sw (fun () ->
          Eio.Promise.await seen;
          Alcotest.(check int) "informational policy calls" 0 !calls;
          Eio.Promise.resolve resolve_continue ());
      let result = C.request client ~method_:"GET" ~url ~on_head:(fun ~status ~headers ->
          incr calls; Alcotest.(check int) "only final status" 200 status;
          check_headers (provenance @ [ ("Content-Length", "3") ]) headers;
          if skip then `Skip else `Read) () in
      if skip then (match result with
          | Ok { status = 200; body = `Skipped; _ } -> ()
          | _ -> fail "informational skip failed")
      else expect_read 200 (provenance @ [ ("Content-Length", "3") ]) "abc" result;
      Alcotest.(check int) "one final-head policy call" 1 !calls;
      Eio.Promise.await done_)

let upgrade () =
  (* ^nhttp-bx60 ^nhttp-32fq *)
  with_server
    (fun flow _ -> Eio.Flow.copy_string "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n" flow; closed flow)
    (fun _ _ client url done_ ->
      match C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ -> fail "policy received 101") () with
      | Error (`Protocol _) -> Eio.Promise.await done_
      | _ -> fail "101 was accepted")

let info_eof () =
  (* ^nhttp-bx60 ^nhttp-32fq *)
  with_server
    (fun flow raw -> Eio.Flow.copy_string "HTTP/1.1 103 Early Hints\r\n\r\n" flow; Eio.Resource.close raw)
    (fun _ _ client url done_ ->
      match C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ -> fail "policy received informational head") () with
      | Error `Closed -> Eio.Promise.await done_
      | _ -> fail "informational-only EOF became final")

let budget_heads () =
  (* ^nhttp-bx60 ^nhttp-32fq *)
  let info = "HTTP/1.1 103 Early Hints\r\n\r\n" in
  let wire = String.concat "" (List.init 1300 (fun _ -> info)) in
  with_server
    (fun flow _ ->
      Eio.Flow.copy_string wire flow; closed flow)
    (fun _ _ client url done_ ->
      match C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ -> fail "oversized informationals reached policy") () with
      | Error (`Protocol _) -> Eio.Promise.await done_
      | _ -> fail "unbounded informational heads")

let trailers () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-oaw6 ^nhttp-bx60 ^nhttp-32fq *)
  let framing = "Transfer-Encoding: chunked\r\n" in
  let headers = provenance @ [ ("Transfer-Encoding", "chunked") ] in
  let prefix = "1\r\na\r\n0\r\n" in
  let exact = "X: " ^ String.make (32768 - 7) 'a' ^ "\r\n\r\n" in
  List.iter (fun (wire, good) ->
      with_server
        (fun flow _ -> Eio.Flow.copy_string (head 200 framing ^ prefix ^ wire) flow; closed flow)
        (fun _ _ client url done_ ->
          let result = C.request client ~method_:"GET" ~url () in
          if good then expect_read 200 headers "a" result
          else expect_body 200 headers (function `Malformed _ -> true | _ -> false) result;
          Eio.Promise.await done_))
    [ ("X-One: a\r\nX-Two: b\r\n\r\n", true);
      (exact, true); ("X: " ^ String.make (32768 - 6) 'a' ^ "\r\n\r\n", false);
      (String.concat "" (List.init 4097 (fun _ -> "X: abc\r\n")) ^ "\r\n", false) ];
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] (prefix ^ "X: value\r\n") ((=) `Truncated)

let tls_body_failure () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-hpo2 ^nhttp-32fq *)
  let arrived, resolve_arrived = Eio.Promise.create () in
  with_server ~tls:true
    (fun flow raw ->
      Eio.Flow.copy_string (head 200 "Content-Length: 6\r\n" ^ "abc") flow;
      Eio.Promise.await arrived;
      (* Partial ciphertext record; unlike a clean close, TLS must diagnose it. *)
      Eio.Flow.copy_string "\x17\x03\x03\x00\x20partial" raw;
      Eio.Resource.close raw)
    (fun _ _ client url done_ ->
      expect_body 200 (provenance @ [ ("Content-Length", "6") ])
        (function `Tls _ -> true | _ -> false)
        (C.request client ~method_:"GET" ~url ~on_head:(fun ~status:_ ~headers:_ ->
             Eio.Promise.resolve resolve_arrived (); `Read) ());
      Eio.Promise.await done_)

let cases =
  [ Alcotest.test_case "final provenance nhttp-dlp2 nhttp-j7cz nhttp-oaw6" `Quick final_provenance;
    Alcotest.test_case "overflow nhttp-dlp2 nhttp-j7cz nhttp-hpo2 nhttp-8ixg" `Quick bounded_body;
    Alcotest.test_case "skip nhttp-uhrh nhttp-w60z nhttp-3bbt nhttp-w5yp nhttp-jxpd nhttp-ey81 nhttp-bx60 nhttp-8ixg" `Quick skip_matrix;
    Alcotest.test_case "default read nhttp-uhrh nhttp-3bbt nhttp-w5yp nhttp-jxpd nhttp-ey81 nhttp-8ixg" `Quick default_read_and_empty;
    Alcotest.test_case "pre-head idle nhttp-v147 nhttp-dgoe" `Quick (fun () -> timeout_phase ~after_head:false ~idle:true);
    Alcotest.test_case "pre-head deadline nhttp-v147 nhttp-dgoe" `Quick (fun () -> timeout_phase ~after_head:false ~idle:false);
    Alcotest.test_case "body idle nhttp-dlp2 nhttp-j7cz nhttp-v147 nhttp-dgoe nhttp-hpo2" `Quick (fun () -> timeout_phase ~after_head:true ~idle:true);
    Alcotest.test_case "body deadline nhttp-dlp2 nhttp-j7cz nhttp-v147 nhttp-dgoe nhttp-hpo2" `Quick (fun () -> timeout_phase ~after_head:true ~idle:false);
    Alcotest.test_case "pre-head cancellation nhttp-v147 nhttp-0d9e nhttp-32fq" `Quick (fun () -> cancellation ~after_head:false);
    Alcotest.test_case "body cancellation nhttp-v147 nhttp-0d9e nhttp-32fq" `Quick (fun () -> cancellation ~after_head:true);
    Alcotest.test_case "policy exception nhttp-0d9e nhttp-32fq" `Quick policy_exceptions;
    Alcotest.test_case "100 103 read nhttp-bx60 nhttp-8ixg nhttp-32fq" `Quick (informationals ~skip:false ~split:false);
    Alcotest.test_case "100 103 split skip nhttp-bx60 nhttp-8ixg nhttp-32fq" `Quick (informationals ~skip:true ~split:true);
    Alcotest.test_case "TLS 100 103 split read nhttp-bx60 nhttp-8ixg nhttp-32fq" `Quick (informationals ~tls:true ~skip:false ~split:true);
    Alcotest.test_case "101 nhttp-bx60 nhttp-32fq" `Quick upgrade;
    Alcotest.test_case "informational EOF nhttp-bx60 nhttp-32fq" `Quick info_eof;
    Alcotest.test_case "informational budget nhttp-bx60 nhttp-32fq" `Quick budget_heads;
    Alcotest.test_case "trailers nhttp-dlp2 nhttp-j7cz nhttp-oaw6 nhttp-bx60 nhttp-32fq" `Quick trailers;
    Alcotest.test_case "TLS body fault nhttp-dlp2 nhttp-j7cz nhttp-hpo2 nhttp-32fq" `Quick tls_body_failure ]
