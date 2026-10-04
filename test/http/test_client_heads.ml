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
let with_server ?(tls = false) ?(abrupt = false) ?mock_clock script test =
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 5. (fun () ->
          Eio.Switch.run (fun sw ->
              let listener =
                Eio.Net.listen ~sw ~reuse_addr:true ~backlog:1 env#net
                  (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
              in
              let port =
                match Eio.Net.listening_addr listener with
                | `Tcp (_, port) -> port
                | _ -> assert false
              in
              let url =
                Printf.sprintf "%s://localhost:%d/" (if tls then "https" else "http") port
              in
              let config = C.tls ~ca_file:"localhost.crt" () in
              let clock =
                match mock_clock with
                | None -> (env#clock :> float Eio.Time.clock_ty Eio.Resource.t)
                | Some clock -> (clock :> float Eio.Time.clock_ty Eio.Resource.t)
              in
              let client = C.create ~sw ~net:env#net ~clock ~tls:config () in
              let peer_closed, resolve_closed = Eio.Promise.create () in
              Eio.Fiber.both
                (fun () ->
                  let raw, _ = Eio.Net.accept ~sw listener in
                  let flow =
                    if tls then
                      let ctx =
                        Ssl.create_server_ctx ~certificate_chain_file:"localhost.crt"
                          ~private_key_file:"localhost.key" ~alpn_protocols:[ "http/1.1" ]
                          ()
                      in
                      let ssl = Ssl.create_server_ssl ctx in
                      Tls.create ~raw:(raw :> Tls.ty Eio.Resource.t) ~ssl
                    else (raw :> Tls.ty Eio.Resource.t)
                  in
                  Fun.protect
                    ~finally:(fun () ->
                      try
                        if abrupt then Eio.Resource.close raw else Eio.Resource.close flow
                      with
                      | Eio.Io _ | End_of_file -> ()
                      | exn when Option.is_some (Tls.failure_message exn) -> ())
                    (fun () ->
                      read_request flow;
                      script flow raw;
                      Eio.Promise.resolve resolve_closed ()))
                (fun () -> test env sw client url peer_closed))))

let provenance = [ ("X-Provenance", "first"); ("X-Provenance", "second") ]

let head status framing =
  Printf.sprintf
    "HTTP/1.1 %d Test\r\nX-Provenance: first\r\nX-Provenance: second\r\n%s\r\n" status
    framing

let expect_read status headers body = function
  | Ok { C.status = got; headers = got_headers; body = `Read bytes } ->
      Alcotest.(check int) "final status" status got;
      check_headers headers got_headers;
      Alcotest.(check string) "exact body" body (Bytes.to_string bytes)
  | _ -> fail "expected an acquired final body"

let expect_body status headers matches = function
  | Error (`Body (failure : C.body_failure)) ->
      Alcotest.(check int) "known final status" status failure.status;
      check_headers headers failure.headers;
      if not (matches failure.reason) then fail "wrong post-head reason"
  | _ -> fail "body failure lost final head"

let bytes_failure ?(tls = false) ?(limit = 1048576) status framing body matches =
  let headers = provenance @ framing in
  let framing_wire =
    String.concat "" (List.map (fun (k, v) -> k ^ ": " ^ v ^ "\r\n") framing)
  in
  with_server ~tls
    (fun flow raw ->
      Eio.Flow.copy_string (head status framing_wire ^ body) flow;
      Eio.Flow.shutdown raw `Send;
      closed raw)
    (fun _ _ client url done_ ->
      expect_body status headers matches
        (C.request client ~method_:"GET" ~url ~max_body_bytes:limit ());
      Eio.Promise.await done_)

let final_provenance () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-dgoe *)
  List.iter
    (fun status ->
      bytes_failure status [ ("Content-Length", "6") ] "abc" (( = ) `Truncated))
    [ 401; 200 ];
  bytes_failure 200 [ ("Transfer-Encoding", "chunked") ] "4\r\nab" (( = ) `Truncated);
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    "nope\r\n"
    (function `Malformed _ -> true | _ -> false);
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    "2\r\nabX\r\n"
    (function `Malformed _ -> true | _ -> false)

let bounded_body () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-8ixg *)
  List.iter
    (fun status ->
      List.iter
        (fun (framing, body) ->
          bytes_failure ~limit:3 status framing body (( = ) `Too_large))
        [
          ([ ("Content-Length", "4") ], "");
          ([ ("Transfer-Encoding", "chunked") ], "4\r\n");
          ([], "four");
        ])
    [ 401; 200 ];
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    "-1\r\n"
    (function `Malformed _ -> true | _ -> false)

let skip_matrix ?(tls = false) () =
  (* ^nhttp-3bbt ^nhttp-w5yp ^nhttp-jxpd ^nhttp-v147 ^nhttp-dgoe ^nhttp-8ixg *)
  List.iter
    (fun (method_, status) ->
      List.iter
        (fun framing ->
          let calls = ref 0 in
          let wire =
            String.concat "" (List.map (fun (k, v) -> k ^ ": " ^ v ^ "\r\n") framing)
          in
          let expected = provenance @ framing in
          with_server ~tls
            (fun flow _ ->
              Eio.Flow.copy_string (head status wire) flow;
              closed flow)
            (fun _ _ client url done_ ->
              let on_head ~status:got ~headers =
                incr calls;
                Alcotest.(check int) "policy status" status got;
                check_headers expected headers;
                `Skip
              in
              (match C.request client ~method_ ~url ~max_body_bytes:0 ~on_head () with
              | Ok { status = got; headers; body = `Skipped } ->
                  Alcotest.(check int) "skipped status" status got;
                  check_headers expected headers
              | _ -> fail "skip waited for or interpreted the body");
              Alcotest.(check int) "one policy call" 1 !calls;
              Eio.Promise.await done_))
        [
          [ ("Content-Length", "999999999") ];
          [ ("Transfer-Encoding", "nonsense") ];
          [];
          [ ("Content-Length", "0") ];
          [ ("Transfer-Encoding", "chunked") ];
        ])
    [
      ("GET", 200);
      ("GET", 401);
      ("GET", 429);
      ("GET", 503);
      ("GET", 302);
      ("HEAD", 200);
      ("GET", 204);
      ("GET", 304);
    ]

let default_read_and_empty () =
  (* ^nhttp-v147 ^nhttp-8ixg *)
  List.iter
    (fun (method_, status, body) ->
      with_server
        (fun flow _ ->
          Eio.Flow.copy_string (head status "Content-Length: 3\r\n" ^ body) flow;
          closed flow)
        (fun _ _ client url done_ ->
          expect_read status
            (provenance @ [ ("Content-Length", "3") ])
            body
            (C.request client ~method_ ~url ());
          Eio.Promise.await done_))
    [
      ("GET", 200, "abc");
      ("GET", 401, "abc");
      ("GET", 302, "abc");
      ("HEAD", 200, "");
      ("GET", 204, "");
      ("GET", 304, "");
    ];
  with_server
    (fun flow _ ->
      Eio.Flow.copy_string (head 200 "Content-Length: 0\r\n") flow;
      closed flow)
    (fun _ _ client url done_ ->
      expect_read 200
        (provenance @ [ ("Content-Length", "0") ])
        ""
        (C.request client ~method_:"GET" ~url ());
      Eio.Promise.await done_)

let connection_reset () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-32fq *)
  List.iter
    (fun status ->
      let admitted, resolve_admitted = Eio.Promise.create () in
      with_server ~abrupt:true
        (fun flow raw ->
          let fd = Option.get (Eio_unix.Resource.fd_opt raw) in
          Eio_unix.Fd.use_exn "HTTP reset fixture" fd (fun fd ->
              Unix.setsockopt_optint fd Unix.SO_LINGER (Some 0));
          Eio.Flow.copy_string (head status "Content-Length: 2\r\n") flow;
          Eio.Promise.await admitted;
          Eio.Resource.close raw)
        (fun _ _ client url done_ ->
          let on_head ~status:_ ~headers:_ =
            Eio.Promise.resolve resolve_admitted ();
            `Read
          in
          expect_body status
            (provenance @ [ ("Content-Length", "2") ])
            (( = ) `Closed)
            (C.request client ~method_:"GET" ~url ~on_head ());
          Eio.Promise.await done_))
    [ 401; 200 ]

let observed_clock clock registered =
  let module Provider = struct
    type t = unit
    type time = float

    let now () = Eio.Time.now clock

    let sleep_until () time =
      Eio.Stream.add registered time;
      Eio.Time.sleep_until clock time
  end in
  Eio.Resource.T ((), Eio.Time.Pi.clock (module Provider))

let timeout_phase ?(tls = false) ?(interim = false) ~after_head ~idle () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-w60z ^nhttp-dgoe ^nhttp-32fq *)
  let clock = Eio_mock.Clock.make () in
  let registered = Eio.Stream.create 128 in
  let observed = observed_clock clock registered in
  let ready, resolve_ready = Eio.Promise.create () in
  let finished, resolve_finished = Eio.Promise.create () in
  with_server ~tls ~mock_clock:observed
    (fun flow _ ->
      if after_head then Eio.Flow.copy_string (head 401 "Content-Length: 2\r\n") flow
      else (
        if interim then
          Eio.Flow.copy_string
            "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\n\r\n" flow;
        Eio.Promise.resolve resolve_ready ());
      closed flow)
    (fun _ sw client url done_ ->
      Eio.Fiber.fork ~sw (fun () ->
          Eio.Promise.await ready;
          Eio.Fiber.first
            (fun () ->
              let rec advance () =
                let due = Eio.Stream.take registered in
                Eio_mock.Clock.set_time clock (max (Eio.Time.now clock) (due +. 0.001));
                advance ()
              in
              advance ())
            (fun () -> Eio.Promise.await finished));
      let delay = Ox.Duration.ms 30 in
      let result =
        C.request client ~method_:"GET" ~url
          ?deadline:(if idle then None else Some delay)
          ?response_idle:(if idle then Some delay else None)
          ~on_head:(fun ~status:_ ~headers:_ ->
            Eio.Promise.resolve resolve_ready ();
            `Read)
          ()
      in
      Eio.Promise.resolve resolve_finished ();
      (if after_head then
         expect_body 401
           (provenance @ [ ("Content-Length", "2") ])
           (( = ) (if idle then `Idle_timeout else `Timeout))
           result
       else
         match result with
         | Error `Timeout when not idle -> ()
         | Error `Idle_timeout when idle -> ()
         | _ -> fail "pre-head timeout acquired phantom provenance");
      Eio.Promise.await done_)

let cancellation ?(tls = false) ~after_head () =
  (* ^nhttp-hpo2 ^nhttp-dgoe ^nhttp-32fq *)
  let arrived, resolve_arrived = Eio.Promise.create () in
  with_server ~tls
    (fun flow _ ->
      if after_head then Eio.Flow.copy_string (head 200 "Content-Length: 2\r\n") flow
      else Eio.Promise.resolve resolve_arrived ();
      closed flow)
    (fun _ _ client url done_ ->
      let propagated = ref false in
      Eio.Cancel.sub (fun cc ->
          Eio.Fiber.both
            (fun () ->
              Eio.Promise.await arrived;
              Eio.Cancel.cancel cc Exit)
            (fun () ->
              match
                C.request client ~method_:"GET" ~url
                  ~on_head:(fun ~status:_ ~headers:_ ->
                    Eio.Promise.resolve resolve_arrived ();
                    `Read)
                  ()
              with
              | _ -> fail "external cancellation became a result"
              | exception Eio.Cancel.Cancelled _ -> propagated := true));
      Alcotest.(check bool) "original cancellation propagated" true !propagated;
      Eio.Promise.await done_)

exception Policy_defect of int

let policy_exceptions ?(tls = false) () =
  (* ^nhttp-hpo2 ^nhttp-dgoe ^nhttp-32fq *)
  List.iter
    (fun original ->
      with_server ~tls
        (fun flow _ ->
          Eio.Flow.copy_string (head 200 "Content-Length: 100\r\n") flow;
          closed flow)
        (fun _ _ client url done_ ->
          let original_trace = ref "" in
          let on_head ~status:_ ~headers:_ =
            try raise original
            with exn ->
              let trace = Printexc.get_raw_backtrace () in
              original_trace := Printexc.raw_backtrace_to_string trace;
              Printexc.raise_with_backtrace exn trace
          in
          (* ^nhttp-hpo2 ^nlintc-du4v: reify the caller exception, including the
             cancellation fixture, so the same identity/backtrace assertions inspect it. *)
          let (`Raised (exn, trace)) =
            match C.request client ~method_:"GET" ~url ~on_head () with
            | _ -> fail "policy exception became typed HTTP error"
            | exception exn -> `Raised (exn, Printexc.get_raw_backtrace ())
          in
          Alcotest.(check bool) "same exception object" true (exn == original);
          Alcotest.(check bool)
            "policy backtrace retained" true
            (!original_trace <> ""
            && String.starts_with ~prefix:!original_trace
                 (Printexc.raw_backtrace_to_string trace));
          Eio.Promise.await done_))
    [
      Policy_defect 42;
      Tls.Testing.failure "caller TLS-shaped defect";
      Failure "caller defect";
      Eio.Time.Timeout;
      Eio.Cancel.Cancelled Exit;
      End_of_file;
      Eio.Net.err (Eio.Net.Connection_failure Eio.Net.Timeout);
    ]

let informationals ?(tls = false) ?(order = [ 100; 103; 103 ]) ~skip ~split () =
  (* ^nhttp-oaw6 ^nhttp-3bbt ^nhttp-8ixg ^nhttp-32fq *)
  let seen, resolve_seen = Eio.Promise.create () in
  let continue, resolve_continue = Eio.Promise.create () in
  let calls = ref 0 in
  let provisional =
    String.concat ""
      (List.map
         (fun status ->
           Printf.sprintf "HTTP/1.1 %d Interim\r\nX-Interim: ignored\r\n\r\n" status)
         order)
  in
  let final = head 200 "Content-Length: 3\r\n" in
  with_server ~tls
    (fun flow _ ->
      if split then (
        Eio.Flow.copy_string
          (provisional ^ String.sub final 0 (String.length final - 1))
          flow;
        Eio.Promise.resolve resolve_seen ();
        Eio.Promise.await continue;
        Eio.Flow.copy_string "\n" flow)
      else Eio.Flow.copy_string (provisional ^ final) flow;
      if not skip then Eio.Flow.copy_string "abc" flow;
      closed flow)
    (fun _ sw client url done_ ->
      if split then
        Eio.Fiber.fork ~sw (fun () ->
            Eio.Promise.await seen;
            Alcotest.(check int) "informational policy calls" 0 !calls;
            Eio.Promise.resolve resolve_continue ());
      let result =
        C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status ~headers ->
            incr calls;
            Alcotest.(check int) "only final status" 200 status;
            check_headers (provenance @ [ ("Content-Length", "3") ]) headers;
            if skip then `Skip else `Read)
          ()
      in
      if skip then
        match result with
        | Ok { status = 200; body = `Skipped; _ } -> ()
        | _ -> fail "informational skip failed"
      else expect_read 200 (provenance @ [ ("Content-Length", "3") ]) "abc" result;
      Alcotest.(check int) "one final-head policy call" 1 !calls;
      Eio.Promise.await done_)

let upgrade () =
  (* ^nhttp-0d9e ^nhttp-32fq *)
  with_server
    (fun flow _ ->
      Eio.Flow.copy_string
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n" flow;
      closed flow)
    (fun _ _ client url done_ ->
      match
        C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ -> fail "policy received 101")
          ()
      with
      | Error (`Protocol _) -> Eio.Promise.await done_
      | _ -> fail "101 was accepted")

let info_eof () =
  (* ^nhttp-oaw6 ^nhttp-ey81 ^nhttp-32fq *)
  with_server
    (fun flow raw ->
      Eio.Flow.copy_string "HTTP/1.1 103 Early Hints\r\n\r\n" flow;
      Eio.Resource.close raw)
    (fun _ _ client url done_ ->
      match
        C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ -> fail "policy received informational head")
          ()
      with
      | Error `Closed -> Eio.Promise.await done_
      | _ -> fail "informational-only EOF became final")

let budget_heads () =
  (* ^nhttp-oaw6 ^nhttp-ey81 ^nhttp-32fq *)
  let info = "HTTP/1.1 103 Early Hints\r\n\r\n" in
  let wire = String.concat "" (List.init 1300 (fun _ -> info)) in
  with_server
    (fun flow _ ->
      Eio.Flow.copy_string wire flow;
      closed flow)
    (fun _ _ client url done_ ->
      match
        C.request client ~method_:"GET" ~url
          ~on_head:(fun ~status:_ ~headers:_ ->
            fail "oversized informationals reached policy")
          ()
      with
      | Error (`Protocol _) -> Eio.Promise.await done_
      | _ -> fail "unbounded informational heads")

let trailers ?(tls = false) () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-dgoe ^nhttp-bx60 ^nhttp-32fq *)
  let framing = "Transfer-Encoding: chunked\r\n" in
  let headers = provenance @ [ ("Transfer-Encoding", "chunked") ] in
  let prefix = "1\r\na\r\n0\r\n" in
  let exact = "X: " ^ String.make (32768 - 7) 'a' ^ "\r\n\r\n" in
  List.iter
    (fun (wire, good) ->
      with_server ~tls
        (fun flow _ ->
          Eio.Flow.copy_string (head 200 framing ^ prefix ^ wire) flow;
          closed flow)
        (fun _ _ client url done_ ->
          let result = C.request client ~method_:"GET" ~url () in
          if good then expect_read 200 headers "a" result
          else
            expect_body 200 headers (function `Malformed _ -> true | _ -> false) result;
          Eio.Promise.await done_))
    [
      ("X-One: a\r\nX-Two: b\r\n\r\n", true);
      ("X-!#$%&'*+-.^_`|~: \t\x80\xff\r\n\r\n", true);
      ("missing-colon\r\n\r\n", false);
      (": empty-name\r\n\r\n", false);
      ("X Bad: value\r\n\r\n", false);
      ("X : value\r\n\r\n", false);
      ("X: value\x00\r\n\r\n", false);
      ("X: value\x7f\r\n\r\n", false);
      (exact, true);
      ("X: " ^ String.make (32768 - 6) 'a' ^ "\r\n\r\n", false);
      (String.concat "" (List.init 4097 (fun _ -> "X: abc\r\n")) ^ "\r\n", false);
    ];
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    (prefix ^ "X: value\r\n") (( = ) `Truncated);
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    (prefix ^ "missing-colon\r\n\r\n")
    (function `Malformed _ -> true | _ -> false);
  bytes_failure 200
    [ ("Transfer-Encoding", "chunked") ]
    (prefix ^ ": empty-name\r\n\r\n")
    (function `Malformed _ -> true | _ -> false)

let tls_body_failure () =
  (* ^nhttp-dlp2 ^nhttp-j7cz ^nhttp-uhrh ^nhttp-32fq *)
  let arrived, resolve_arrived = Eio.Promise.create () in
  with_server ~tls:true ~abrupt:true
    (fun flow raw ->
      Eio.Flow.copy_string (head 200 "Content-Length: 6\r\n" ^ "abc") flow;
      Eio.Promise.await arrived;
      (* Partial ciphertext record; unlike a clean close, TLS must diagnose it. *)
      Eio.Flow.copy_string "\x17\x03\x03\x00\x20partial" raw;
      Eio.Resource.close raw)
    (fun _ _ client url done_ ->
      expect_body 200
        (provenance @ [ ("Content-Length", "6") ])
        (function `Tls _ -> true | _ -> false)
        (C.request client ~method_:"GET" ~url
           ~on_head:(fun ~status:_ ~headers:_ ->
             Eio.Promise.resolve resolve_arrived ();
             `Read)
           ());
      Eio.Promise.await done_)

let acquired_framing () =
  (* ^nhttp-8ixg ^nhttp-dgoe ^nhttp-32fq *)
  List.iter
    (fun tls ->
      List.iter
        (fun (framing, wire, body, eof) ->
          with_server ~tls
            (fun flow _ ->
              Eio.Flow.copy_string (head 200 framing ^ wire) flow;
              if eof then Eio.Flow.shutdown flow `Send;
              closed flow)
            (fun _ _ client url done_ ->
              let expected =
                provenance
                @ if framing = "" then [] else [ ("Transfer-Encoding", "chunked") ]
              in
              expect_read 200 expected body (C.request client ~method_:"GET" ~url ());
              Eio.Promise.await done_))
        [
          ("Transfer-Encoding: chunked\r\n", "3\r\nabc\r\n0\r\n\r\n", "abc", false);
          ("Transfer-Encoding: chunked\r\n", "0\r\n\r\n", "", false);
          ("", "abc", "abc", true);
          ("", "", "", true);
        ])
    [ false; true ]

let caller_policies () =
  (* ^nhttp-v147 ^nhttp-3bbt ^nhttp-w5yp ^nhttp-32fq *)
  List.iter
    (fun policy ->
      List.iter
        (fun status ->
          let disposition = policy status in
          with_server
            (fun flow _ ->
              Eio.Flow.copy_string (head status "Content-Length: 3\r\n") flow;
              if disposition = `Read then Eio.Flow.copy_string "abc" flow;
              closed flow)
            (fun _ _ client url done_ ->
              let result =
                C.request client ~method_:"GET" ~url
                  ~on_head:(fun ~status ~headers:_ -> policy status)
                  ()
              in
              (match (disposition, result) with
              | `Skip, Ok { C.body = `Skipped; _ } -> ()
              | `Read, result ->
                  expect_read status
                    (provenance @ [ ("Content-Length", "3") ])
                    "abc" result
              | _ -> fail "kernel overrode caller policy");
              Eio.Promise.await done_))
        [ 200; 401; 500; 302 ])
    [
      (fun status -> if status >= 200 && status < 300 then `Read else `Skip);
      (fun status -> if status = 401 then `Skip else `Read);
      (fun _ -> `Read);
    ]

let informational_exact_bound () =
  (* ^nhttp-ey81 ^nhttp-oaw6 ^nhttp-32fq *)
  let interim length =
    let prefix = "HTTP/1.1 103 Early Hints\r\nX: " in
    prefix ^ String.make (length - String.length prefix - 4) 'a' ^ "\r\n\r\n"
  in
  List.iter
    (fun over ->
      with_server
        (fun flow _ ->
          let wire = interim 16384 ^ interim (if over then 16385 else 16384) in
          Eio.Flow.copy_string wire flow;
          if not over then
            Eio.Flow.copy_string (head 200 "Content-Length: 3\r\n" ^ "abc") flow;
          closed flow)
        (fun _ _ client url done_ ->
          let calls = ref 0 in
          let result =
            C.request client ~method_:"GET" ~url
              ~on_head:(fun ~status:_ ~headers:_ ->
                incr calls;
                `Read)
              ()
          in
          if over then
            match result with
            | Error (`Protocol _) -> Alcotest.(check int) "no final policy" 0 !calls
            | _ -> fail "one byte over informational budget accepted"
          else (
            expect_read 200 (provenance @ [ ("Content-Length", "3") ]) "abc" result;
            Alcotest.(check int) "final policy" 1 !calls);
          Eio.Promise.await done_))
    [ false; true ]

let cases =
  [
    Alcotest.test_case
      "latched connection reset nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-32fq" `Quick
      connection_reset;
    Alcotest.test_case "both body framings nhttp-8ixg nhttp-dgoe nhttp-32fq" `Quick
      acquired_framing;
    Alcotest.test_case "caller policies nhttp-v147 nhttp-3bbt nhttp-w5yp nhttp-32fq"
      `Quick caller_policies;
    Alcotest.test_case "informational exact bound nhttp-ey81 nhttp-oaw6 nhttp-32fq" `Quick
      informational_exact_bound;
    Alcotest.test_case
      "TLS skip matrix nhttp-3bbt nhttp-w5yp nhttp-jxpd nhttp-8ixg nhttp-32fq" `Quick
      (skip_matrix ~tls:true);
    Alcotest.test_case "TLS policy exceptions nhttp-hpo2 nhttp-dgoe nhttp-32fq" `Quick
      (policy_exceptions ~tls:true);
    Alcotest.test_case "final provenance nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-dgoe"
      `Quick final_provenance;
    Alcotest.test_case "overflow nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-8ixg" `Quick
      bounded_body;
    Alcotest.test_case
      "skip nhttp-3bbt nhttp-w5yp nhttp-jxpd nhttp-v147 nhttp-dgoe nhttp-8ixg" `Quick
      skip_matrix;
    Alcotest.test_case "default read nhttp-v147 nhttp-8ixg" `Quick default_read_and_empty;
    Alcotest.test_case "pre-head idle nhttp-dlp2 nhttp-dgoe" `Quick (fun () ->
        timeout_phase ~after_head:false ~idle:true ());
    Alcotest.test_case "pre-head deadline nhttp-dlp2 nhttp-w60z nhttp-dgoe" `Quick
      (fun () -> timeout_phase ~after_head:false ~idle:false ());
    Alcotest.test_case "body idle nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-dgoe" `Quick
      (fun () -> timeout_phase ~after_head:true ~idle:true ());
    Alcotest.test_case "body deadline nhttp-dlp2 nhttp-j7cz nhttp-w60z nhttp-dgoe" `Quick
      (fun () -> timeout_phase ~after_head:true ~idle:false ());
    Alcotest.test_case "pre-head cancellation nhttp-hpo2 nhttp-dgoe nhttp-32fq" `Quick
      (fun () -> cancellation ~after_head:false ());
    Alcotest.test_case "body cancellation nhttp-hpo2 nhttp-dgoe nhttp-32fq" `Quick
      (fun () -> cancellation ~after_head:true ());
    Alcotest.test_case "policy exceptions nhttp-hpo2 nhttp-dgoe nhttp-32fq" `Quick
      policy_exceptions;
    Alcotest.test_case "100 then final nhttp-oaw6 nhttp-8ixg nhttp-32fq" `Quick
      (informationals ~order:[ 100 ] ~skip:false ~split:false);
    Alcotest.test_case "103 100 split skip nhttp-oaw6 nhttp-3bbt nhttp-32fq" `Quick
      (informationals ~order:[ 103; 100; 103 ] ~skip:true ~split:true);
    Alcotest.test_case "TLS 103 100 split read nhttp-oaw6 nhttp-8ixg nhttp-32fq" `Quick
      (informationals ~tls:true ~order:[ 103; 100 ] ~skip:false ~split:true);
    Alcotest.test_case "101 nhttp-0d9e nhttp-32fq" `Quick upgrade;
    Alcotest.test_case "informational EOF nhttp-dlp2 nhttp-oaw6 nhttp-ey81 nhttp-32fq"
      `Quick info_eof;
    Alcotest.test_case "informational budget nhttp-oaw6 nhttp-ey81 nhttp-32fq" `Quick
      budget_heads;
    Alcotest.test_case "trailers nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-bx60 nhttp-32fq"
      `Quick trailers;
    Alcotest.test_case "TLS body fault nhttp-dlp2 nhttp-j7cz nhttp-uhrh nhttp-32fq" `Quick
      tls_body_failure;
    Alcotest.test_case "informational idle nhttp-ey81 nhttp-oaw6 nhttp-32fq" `Quick
      (fun () -> timeout_phase ~interim:true ~after_head:false ~idle:true ());
    Alcotest.test_case
      "informational deadline nhttp-ey81 nhttp-oaw6 nhttp-w60z nhttp-32fq" `Quick
      (fun () -> timeout_phase ~interim:true ~after_head:false ~idle:false ());
    Alcotest.test_case "TLS trailers nhttp-bx60 nhttp-uhrh nhttp-32fq" `Quick
      (trailers ~tls:true);
    Alcotest.test_case "TLS body idle nhttp-uhrh nhttp-dgoe nhttp-32fq" `Quick (fun () ->
        timeout_phase ~tls:true ~after_head:true ~idle:true ());
    Alcotest.test_case "TLS body deadline nhttp-w60z nhttp-dgoe nhttp-32fq" `Quick
      (fun () -> timeout_phase ~tls:true ~after_head:true ~idle:false ());
    Alcotest.test_case "TLS body cancellation nhttp-hpo2 nhttp-dgoe nhttp-32fq" `Quick
      (fun () -> cancellation ~tls:true ~after_head:true ());
  ]
