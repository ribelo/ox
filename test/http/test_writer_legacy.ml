(* Ported from v1:test/http/test_eta_http_h1_write.ml.
   Covers nhttp-qvak and nhttp-ed7t without the removed effectful transport. *)
let h1_injection_cases =
  [
    ("value CRLF", [ ("X-Good", "ok\r\ninjected: 1") ]);
    ("name CRLF", [ ("x-good\r\ninjected", "1") ]);
    ("value LF", [ ("X-Good", "ok\ninjected: 1") ]);
    ("value CR", [ ("X-Good", "ok\rinjected: 1") ]);
    ("value obs-fold", [ ("X-Good", "ok\n injected: 1") ]);
    ("name NUL", [ ("x\000bad", "1") ]);
    ("value NUL", [ ("X-Good", "bad\000value") ]);
  ]

let expect_valid = function
  | Ok wire -> wire
  | Error { Eta_http.Error.kind = Header_invalid { reason }; _ } ->
      Alcotest.failf "unexpected writer refusal: %s" reason

let test_reject_header_injection () =
  let url = Eta_http.Url.of_string "https://example.test/path" in
  List.iter
    (fun (name, headers) ->
      match
        Eta_http.H1_write.to_string ~method_:"GET" ~url ~headers
          ~body:Eta_http.H1_write.Empty
      with
      | Error { Eta_http.Error.kind = Header_invalid _; _ } -> ()
      | Ok wire -> Alcotest.failf "%s injected into %S" name wire)
    h1_injection_cases

let test_fixed_request () =
  let url = Eta_http.Url.of_string "https://example.test/echo?test=1" in
  let wire =
    Eta_http.H1_write.to_string ~method_:"POST" ~url ~headers:[]
      ~body:(Eta_http.H1_write.Fixed [ Bytes.of_string "abc" ])
    |> expect_valid
  in
  Alcotest.(check bool)
    "origin-form" true
    (String.starts_with ~prefix:"POST /echo?test=1 HTTP/1.1\r\n" wire);
  Alcotest.(check bool) "length" true (String.ends_with ~suffix:"\r\n\r\nabc" wire)

let test_invalid_framing () =
  let url = Eta_http.Url.of_string "http://example.test/echo" in
  List.iter
    (fun headers ->
      match
        Eta_http.H1_write.to_string ~method_:"POST" ~url ~headers
          ~body:(Eta_http.H1_write.Fixed [ Bytes.of_string "abcdef" ])
      with
      | Error { Eta_http.Error.kind = Header_invalid _; _ } -> ()
      | Ok wire -> Alcotest.failf "bad framing accepted: %S" wire)
    [
      [ ("Content-Length", "3") ];
      [ ("Transfer-Encoding", "chunked") ];
      [ ("Content-Length", "6"); ("Content-Length", "3") ];
    ]

let test_parse_response () =
  let raw =
    Bytes.of_string
      "HTTP/1.1 302 Found\r\nLocation: /next\r\nContent-Length: 3\r\n\r\nabc"
  in
  match Eta_http.H1_parse.parse raw ~len:(Bytes.length raw) with
  | Error error -> Alcotest.fail (Eta_http.H1_parse.parse_error_to_string error)
  | Ok parsed ->
      Alcotest.(check int) "status" 302 parsed.status;
      Alcotest.(check string)
        "body" "abc"
        (Bytes.to_string (Eta_http.H1_parse.body_to_bytes raw parsed))

let test_parse_cl_rejection () =
  let raw = Bytes.of_string "HTTP/1.1 200 OK\r\nContent-Length: abc\r\n\r\n" in
  match Eta_http.H1_parse.parse raw ~len:(Bytes.length raw) with
  | Error (Eta_http.H1_parse.Invalid_content_length _) -> ()
  | _ -> Alcotest.fail "invalid length accepted"
