module H = Ox_http
module S = H.Server
module Service = H.Service

let check cond message = if not cond then Alcotest.fail message

let body_text r =
  match S.Response.body r with
  | S.Response.Body.Fixed chunks -> String.concat "" (List.map Bytes.to_string chunks)
  | Empty -> ""
  | Stream _ -> Alcotest.fail "unexpected streaming response"

let expect_ok = function
  | Ok x -> x
  | Error e -> Alcotest.fail (Format.asprintf "%a" S.Error.pp e)

let request ?(method_ = "GET") ?(path = "/notes/23") ?(query = None)
    ?(body = S.Body.empty ()) () : S.Request.t =
  {
    id = lazy "1";
    version = H.Version.H1_1;
    scheme = "http";
    authority = Some "localhost";
    method_;
    target = path;
    path;
    query;
    headers = H.Header.empty;
    body;
    trailers = (fun () -> Ok H.Header.empty);
    peer = { address = None; port = None };
    tls = false;
    alpn_protocol = None;
    stream_id = None;
    connection_id = "test";
  }

let service_routes () =
  (* ^hserv-d2p8 ^hserv-e3q9 ^hserv-f4r0 *)
  let router = Service.Router.create () in
  Service.Router.add_exn router ~methods:[ "GET" ] "/notes/{id}" (fun req ->
      match Service.Extractors.Param.string "id" req with
      | Error _ as e -> e
      | Ok id -> (
          match Service.Extractors.Query.all req with
          | Error _ as e -> e
          | Ok pairs ->
              Ok
                (S.Response.text
                   (id ^ ":"
                   ^ Option.value ~default:"" (Service.Extractors.Query.get "q" pairs)))));
  let handler = Service.Router.compile router in
  Alcotest.(check string)
    "parameter and decoded query" "23:a b"
    (body_text (expect_ok (handler (request ~query:(Some "q=a+b") ()))));
  let allowed = expect_ok (handler (request ~method_:"POST" ())) in
  Alcotest.(check int) "method denied" 405 (S.Response.status allowed);
  Alcotest.(check (option string))
    "Allow header" (Some "GET")
    (H.Header.get "allow" (S.Response.headers allowed));
  Alcotest.(check int)
    "path not found" 404
    (S.Response.status (expect_ok (handler (request ~path:"/unknown" ()))));
  (match
     Service.Router.add router ~methods:[ "GET" ] "/notes/{id}" (fun _ ->
         Ok (S.Response.empty ~status:200 ()))
   with
  | Error (Service.Router.Duplicate_route _) -> ()
  | _ -> Alcotest.fail "duplicate registration");
  Service.Router.add_exn router ~methods:[ "GET" ] "/later" (fun _ ->
      Ok (S.Response.empty ~status:200 ()));
  Alcotest.(check int)
    "compiled handler is frozen" 404
    (S.Response.status (expect_ok (handler (request ~path:"/later" ()))));
  match handler (request ~query:(Some "q=%xx") ()) with
  | Error { S.Error.kind = Bad_request _; _ } -> ()
  | _ -> Alcotest.fail "invalid query should be typed bad request"

let body_bound () =
  (* ^hserv-b8m4 ^hserv-d2p8 *)
  let fragments = ref [ Bytes.of_string "abc"; Bytes.of_string "def" ] in
  let body =
    S.Body.of_reader (fun () ->
        match !fragments with
        | [] -> Ok None
        | x :: xs ->
            fragments := xs;
            Ok (Some x))
  in
  (match S.Body.read_all ~max_bytes:5 body with
  | Error { S.Error.kind = Request_body_too_large { limit = 5; length = 6 }; _ } -> ()
  | _ -> Alcotest.fail "bounded extraction rejected");
  let req =
    request ~body:(S.Body.of_reader (fun () -> Ok (Some (Bytes.of_string "x")))) ()
  in
  ignore req

let response input =
  let status_line = Eio.Buf_read.line input in
  let rec headers acc =
    let line = Eio.Buf_read.line input in
    if line = "" then List.rev acc else headers (line :: acc)
  in
  let headers = headers [] in
  let length =
    List.find_map
      (fun line ->
        match String.split_on_char ':' line with
        | name :: value when String.lowercase_ascii name = "content-length" ->
            int_of_string_opt (String.trim (String.concat ":" value))
        | _ -> None)
      headers
  in
  let body = match length with Some n -> Eio.Buf_read.take n input | None -> "" in
  (status_line, headers, body)

let server_exchange () =
  (* ^hserv-a7k2 ^hserv-b8m4 ^hserv-c9n6 *)
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let addr = Eio.Net.listening_addr listener in
          let stop, resolve = Eio.Promise.create () in
          Eio.Fiber.fork ~sw (fun () ->
              S.run_h1_on_socket ~sw ~clock:env#clock ~stop ~socket:listener (fun req ->
                  let message =
                    expect_ok (S.Body.read_all req.S.Request.body) |> Bytes.to_string
                  in
                  Ok (S.Response.text (req.path ^ ":" ^ message))));
          let flow = Eio.Net.connect ~sw env#net addr in
          let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
          Eio.Flow.copy_string
            "POST /one HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\nabc" flow;
          let status, _, body = response input in
          check (String.starts_with ~prefix:"HTTP/1.1 200" status) "POST status";
          Alcotest.(check string) "POST content length" "/one:abc" body;
          Eio.Flow.copy_string
            "POST /two HTTP/1.1\r\n\
             Host: localhost\r\n\
             Transfer-Encoding: chunked\r\n\
             Connection: close\r\n\
             \r\n\
             3\r\n\
             xyz\r\n\
             0\r\n\
             \r\n"
            flow;
          let _, _, body = response input in
          Alcotest.(check string) "chunked second request" "/two:xyz" body;
          Eio.Flow.close flow;
          Eio.Promise.resolve resolve ()))

let bad_request_exchange ~config wire expected =
  (* ^hserv-f4r0: malformed framing and bounded headers/body close the flow. *)
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let addr = Eio.Net.listening_addr listener in
          let stop, resolve = Eio.Promise.create () in
          Eio.Fiber.fork ~sw (fun () ->
              S.run_h1_on_socket ~sw ~clock:env#clock ~stop ~config ~socket:listener
                (fun _ -> Ok (S.Response.text "unexpected handler")));
          Fun.protect
            ~finally:(fun () -> Eio.Promise.resolve resolve ())
            (fun () ->
              let flow = Eio.Net.connect ~sw env#net addr in
              Eio.Flow.copy_string wire flow;
              let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
              Eio.Time.with_timeout_exn env#clock 1.0 (fun () ->
                  let status, headers, _ = response input in
                  check
                    (String.starts_with ~prefix:expected status)
                    "unexpected server status";
                  check
                    (List.exists
                       (fun line -> String.lowercase_ascii line = "connection: close")
                       headers)
                    "server must close rejected connection";
                  try
                    ignore (Eio.Buf_read.take 1 input);
                    Alcotest.fail "bad connection stayed open"
                  with End_of_file -> ());
              Eio.Flow.close flow)))

let malformed_and_limits () =
  let host = "POST /x HTTP/1.1\r\nHost: localhost\r\n" in
  bad_request_exchange ~config:S.Config.default
    (host ^ "Content-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n")
    "HTTP/1.1 400";
  bad_request_exchange ~config:S.Config.default
    (host ^ "Content-Length: +2\r\n\r\n")
    "HTTP/1.1 400";
  let config = { S.Config.default with max_request_body_bytes = 2 } in
  bad_request_exchange ~config (host ^ "Content-Length: 3\r\n\r\n") "HTTP/1.1 413";
  let config = { S.Config.default with max_request_header_bytes = 90 } in
  bad_request_exchange ~config
    (host ^ "X-Long: " ^ String.make 100 'a' ^ "\r\n\r\n")
    "HTTP/1.1 431"

let stop_idle () =
  (* ^hserv-a7k2 ^hserv-f4r0: stop interrupts idle keep-alive. *)
  Eio_main.run (fun env ->
      Eio.Switch.run (fun sw ->
          let listener =
            Eio.Net.listen ~sw ~backlog:2 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
          in
          let stop, resolve = Eio.Promise.create () in
          let finished, notify = Eio.Promise.create () in
          Eio.Fiber.fork ~sw (fun () ->
              S.run_h1_on_socket ~sw ~clock:env#clock ~stop ~socket:listener (fun _ ->
                  Ok (S.Response.text "ok"));
              Eio.Promise.resolve notify ());
          let flow = Eio.Net.connect ~sw env#net (Eio.Net.listening_addr listener) in
          let input = Eio.Buf_read.of_flow ~max_size:65536 flow in
          Eio.Flow.copy_string "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n" flow;
          let _, _, text = response input in
          Alcotest.(check string) "GET body" "ok" text;
          Eio.Promise.resolve resolve ();
          Eio.Time.with_timeout_exn env#clock 1.0 (fun () -> Eio.Promise.await finished);
          Eio.Flow.close flow))

let () =
  Alcotest.run "HTTP server and service"
    [
      ( "service",
        [
          Alcotest.test_case "routes and errors" `Quick service_routes;
          Alcotest.test_case "bounded body" `Quick body_bound;
        ] );
      ( "socket",
        [
          Alcotest.test_case "keep-alive and chunked body" `Quick server_exchange;
          Alcotest.test_case "malformed and oversized" `Quick malformed_and_limits;
          Alcotest.test_case "stop idle connection" `Quick stop_idle;
        ] );
    ]
