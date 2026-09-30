(* ^nstress-ln4z. Libraries: stress_support ox_http ox eio eio_main qcheck-core
   cstruct unix. Crowbar is absent from the switch: QCheck2's integrated shrinking
   supplies bounded QuickCheck-style fuzzing, with deterministic corpus checks. *)
module H = Ox_http
module S = H.Server
module G = QCheck2.Gen

let check condition message = if not condition then failwith message
let input_limit = 8192
let header_limit = 2048
let body_limit = 4096
let print_bytes bytes = Printf.sprintf "%S" (Bytes.to_string bytes)

let response bytes =
  match
    H.H1_parse.parse ~max_header_bytes:header_limit bytes ~len:(Bytes.length bytes)
  with
  | Error error as result ->
      check (H.H1_parse.parse_error_to_string error <> "") "unclassified HTTP error";
      result
  | Ok parsed as result ->
      let span (span : H.Span.t) =
        check
          (span.off >= 0 && span.len >= 0 && span.off <= Bytes.length bytes - span.len)
          "HTTP span outside input"
      in
      span parsed.reason;
      span parsed.body;
      List.iter
        (fun (h : H.H1_parse.header) ->
          span h.name;
          span h.value)
        parsed.headers;
      ignore (H.H1_parse.headers_to_list bytes parsed.headers);
      ignore (H.H1_parse.body_to_bytes bytes parsed);
      result

let websocket ~masked bytes =
  match H.Ws_codec.decode ~masked bytes with
  | Error error as result ->
      check (H.Ws_codec.parse_error_to_string error <> "") "unclassified WS error";
      result
  | Ok (frame, consumed) as result ->
      check (consumed >= 2 && consumed <= Bytes.length bytes) "WS consumed outside input";
      let encoded = H.Ws_codec.encode frame in
      (match H.Ws_codec.decode encoded with
      | Ok (decoded, n) ->
          check (decoded = frame && n = Bytes.length encoded) "WS roundtrip differs"
      | Error error -> failwith (H.Ws_codec.parse_error_to_string error));
      result

let hexadecimal text =
  String.split_on_char ' '
    (String.map (function '\n' | '\r' | '\t' -> ' ' | c -> c) text)
  |> List.filter (fun word -> word <> "")
  |> List.map (fun word -> Char.chr (int_of_string ("0x" ^ word)))
  |> List.to_seq |> Bytes.of_seq

let load_corpus fs directory names =
  List.map
    (fun name -> (name, Bytes.of_string (Eio.Path.load Eio.Path.(fs / directory / name))))
    names

let mutation bytes (kind, position, byte) =
  let n = Bytes.length bytes in
  let position = position mod (n + 1) in
  match kind with
  | 0 when position < n ->
      let out = Bytes.copy bytes in
      Bytes.set out position byte;
      out
  | 1 when position < n ->
      let out = Bytes.copy bytes in
      Bytes.set out position
        (Char.chr (Char.code (Bytes.get out position) lxor Char.code byte));
      out
  | 2 when n < input_limit ->
      let out = Bytes.create (n + 1) in
      Bytes.blit bytes 0 out 0 position;
      Bytes.set out position byte;
      Bytes.blit bytes position out (position + 1) (n - position);
      out
  | 3 when position < n ->
      Bytes.cat (Bytes.sub bytes 0 position)
        (Bytes.sub bytes (position + 1) (n - position - 1))
  | _ -> Bytes.sub bytes 0 position

let byte_gen = G.map Char.chr (G.int_range 0 255)

let bounded_bytes bound =
  G.map
    (fun chars -> Bytes.of_seq (List.to_seq chars))
    (G.list_size (G.int_range 0 bound) byte_gen)

let bytes_gen = bounded_bytes 1024

let fuzz_gen corpus =
  let seed = G.oneof_list (List.map snd corpus) in
  let edit = G.triple (G.int_range 0 4) (G.int_range 0 input_limit) byte_gen in
  let mutated =
    G.map2 (List.fold_left mutation) seed (G.list_size (G.int_range 1 8) edit)
  in
  G.oneof_weighted [ (4, mutated); (1, bytes_gen) ]

let run_property random name count generator property =
  Printf.printf "%s (%d cases)\n%!" name count;
  QCheck2.Test.check_exn ~rand:random
    (QCheck2.Test.make ~name ~count ~print:print_bytes generator (fun bytes ->
         property bytes;
         true))

let every_prefix corpus property =
  List.iter
    (fun (name, bytes) ->
      for length = 0 to Bytes.length bytes - 1 do
        try property (Bytes.sub bytes 0 length)
        with exn ->
          failwith
            (Printf.sprintf "%s truncated at %d: %s" name length (Printexc.to_string exn))
      done)
    corpus

(* The request parser is private. Exercise its real public boundary, not a
   copied parser or a test-only API. Incomplete heads may close on EOF; other
   rejections must be 400/413/431, and body failures must be Server.Error.t. *)
let with_requests env run =
  Eio.Switch.run (fun sw ->
      let socket =
        Eio.Net.listen ~sw ~backlog:8 env#net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let addr = Eio.Net.listening_addr socket in
      let stop, resolve = Eio.Promise.create () in
      let escaped = ref [] and body_errors = ref [] and received = ref [] in
      let config =
        {
          S.Config.default with
          max_request_line_bytes = 1024;
          max_request_header_bytes = header_limit;
          max_request_headers = 32;
          max_request_body_bytes = body_limit;
        }
      in
      Eio.Fiber.fork ~sw (fun () ->
          S.run_h1_on_socket ~sw ~clock:env#clock ~socket ~stop ~config
            ~on_error:(fun exn -> escaped := exn :: !escaped)
            (fun request ->
              match S.Body.read_all ~max_bytes:body_limit request.S.Request.body with
              | Ok body ->
                  received := (request.method_, request.target, body) :: !received;
                  Ok (S.Response.empty ~status:204 ())
              | Error error ->
                  body_errors := error :: !body_errors;
                  Ok (S.Response.empty ~status:400 ())));
      let exchange ?expected bytes =
        escaped := [];
        body_errors := [];
        received := [];
        let output = Buffer.create 128 in
        Eio.Time.with_timeout_exn env#clock 1.0 (fun () ->
            Eio.Switch.run (fun client_sw ->
                let flow = Eio.Net.connect ~sw:client_sw env#net addr in
                let scratch = Cstruct.create 1024 in
                let rec receive () =
                  match Eio.Flow.single_read flow scratch with
                  | n ->
                      check
                        (Buffer.length output + n <= input_limit)
                        "request response exceeded budget";
                      Buffer.add_string output (Cstruct.to_string ~len:n scratch);
                      receive ()
                  | exception End_of_file -> ()
                in
                (* RST/EPIPE can accompany rejection with unread bytes. Only this
                   documented transport error is allowed, never parser exceptions. *)
                try
                  Eio.Flow.copy_string (Bytes.to_string bytes) flow;
                  Eio.Flow.shutdown flow `Send;
                  receive ()
                with Eio.Io (Eio.Net.E (Eio.Net.Connection_reset _), _) -> ()));
        check (!escaped = [])
          ("request parser escaped: "
          ^ String.concat "; " (List.map Printexc.to_string !escaped));
        List.iter
          (fun (error : S.Error.t) ->
            match error.kind with
            | Bad_request { message } ->
                check (message <> "") "empty typed body rejection"
            | Request_body_too_large { limit; length } ->
                check
                  (limit = body_limit && length > limit)
                  "overflowed typed body length"
            | Handler_failed _ ->
                failwith "parser classified body failure as handler error")
          !body_errors;
        (match expected with
        | None -> ()
        | Some request ->
            check (!received = [ request ]) "written request roundtrip differs");
        let wire = Bytes.of_string (Buffer.contents output) in
        let rec statuses offset acc =
          if offset = Bytes.length wire then List.rev acc
          else
            let rest = Bytes.sub wire offset (Bytes.length wire - offset) in
            match response rest with
            | Error error ->
                failwith
                  ("invalid rejection response: " ^ H.H1_parse.parse_error_to_string error)
            | Ok parsed ->
                check
                  (List.mem parsed.status [ 204; 400; 413; 431 ])
                  "untyped request rejection";
                let consumed = parsed.body.off + parsed.body.len in
                check (consumed > 0) "response made no progress";
                statuses (offset + consumed) (parsed.status :: acc)
        in
        statuses 0 []
      in
      Fun.protect
        ~finally:(fun () -> Eio.Promise.resolve resolve ())
        (fun () -> run exchange))

let lengths =
  [
    "0";
    "1";
    "4096";
    "4097";
    string_of_int max_int;
    Int64.to_string (Int64.add (Int64.of_int max_int) 1L);
    "9223372036854775807";
    "18446744073709551615";
    String.make 1000 '9';
    "-1";
    "+1";
    "0x10";
    "1_000";
  ]

let decimal_response length =
  Bytes.of_string ("HTTP/1.1 200 OK\r\nContent-Length: " ^ length ^ "\r\n\r\n")

let decimal_request length =
  Bytes.of_string
    ("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: " ^ length ^ "\r\n\r\n")

let chunk_request length =
  Bytes.of_string
    ("POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" ^ length
   ^ "\r\n")

let ws_length length =
  let bytes = Bytes.make 10 '\000' in
  Bytes.set bytes 0 '\130';
  Bytes.set bytes 1 '\127';
  Bytes.set_int64_be bytes 2 length;
  bytes

let deterministic_responses corpus =
  List.iter
    (fun (_, bytes) ->
      match response bytes with Ok _ -> () | Error _ -> failwith "invalid HTTP corpus")
    corpus;
  every_prefix corpus (fun bytes ->
      match response bytes with
      | Error _ -> ()
      | Ok _ -> failwith "accepted truncated response");
  List.iter
    (fun length ->
      match response (decimal_response length) with
      | Ok parsed ->
          check (length = "0" && parsed.body.len = 0) "accepted absent advertised body"
      | Error _ -> ())
    lengths;
  let oversized =
    Bytes.of_string ("HTTP/1.1 200 OK\r\nX-Fuzz: " ^ String.make 4096 'a' ^ "\r\n\r\n")
  in
  match response oversized with
  | Error (H.H1_parse.Header_section_too_large _) -> ()
  | _ -> failwith "HTTP header limit not enforced"

let deterministic_ws corpus =
  List.iter
    (fun (name, bytes) ->
      let masked = name = "ws/masked-text.hex" in
      (match websocket ~masked bytes with
      | Ok (_, consumed) ->
          check (consumed = Bytes.length bytes) "invalid WS corpus length"
      | Error _ -> failwith ("invalid WS corpus: " ^ name));
      every_prefix
        [ (name, bytes) ]
        (fun prefix ->
          match websocket ~masked prefix with
          | Error _ -> ()
          | Ok _ -> failwith "accepted truncated WS frame"))
    corpus;
  List.iter
    (fun length ->
      let frame : H.Ws_codec.frame =
        { fin = true; opcode = Binary; payload = Bytes.make length 'a' }
      in
      let bytes = H.Ws_codec.encode frame in
      (match websocket ~masked:false bytes with
      | Ok (decoded, n) ->
          check
            (decoded = frame && n = Bytes.length bytes)
            "valid WS length boundary failed"
      | Error error -> failwith (H.Ws_codec.parse_error_to_string error));
      let masked_bytes = H.Ws_codec.encode ~mask:(Bytes.of_string "mask") frame in
      (match websocket ~masked:true masked_bytes with
      | Ok (decoded, n) ->
          check
            (decoded = frame && n = Bytes.length masked_bytes)
            "masked WS boundary failed"
      | Error error -> failwith (H.Ws_codec.parse_error_to_string error));
      List.iter
        (fun n ->
          match websocket ~masked:false (Bytes.sub bytes 0 n) with
          | Error _ -> ()
          | Ok _ -> failwith "accepted length boundary truncation")
        (List.filter
           (fun n -> n < Bytes.length bytes)
           [ 0; 1; 2; min 9 (Bytes.length bytes - 1); Bytes.length bytes - 1 ]))
    [ 0; 1; 125; 126; 65535; 65536 ];
  List.iter
    (fun length ->
      let bytes = ws_length length in
      every_prefix
        [ ("WS 64-bit length", bytes) ]
        (fun prefix -> ignore (websocket ~masked:false prefix));
      match websocket ~masked:false bytes with
      | Error _ -> ()
      | Ok _ -> failwith "accepted advertised WS length")
    [
      125L;
      126L;
      65535L;
      65536L;
      Int64.of_int Sys.max_string_length;
      Int64.succ (Int64.of_int Sys.max_string_length);
      Int64.of_int max_int;
      Int64.max_int;
      Int64.min_int;
      -1L;
    ]

let deterministic_requests corpus exchange =
  List.iter
    (fun (_, bytes) -> check (exchange bytes = [ 204 ]) "invalid request corpus")
    corpus;
  every_prefix corpus (fun bytes ->
      check (not (List.mem 204 (exchange bytes))) "accepted truncated request");
  List.iter
    (fun length ->
      let status =
        if length = "0" then 204
        else
          match int_of_string_opt length with
          | Some n
            when n > body_limit
                 && String.for_all (function '0' .. '9' -> true | _ -> false) length ->
              413
          | _ -> 400
      in
      check
        (exchange (decimal_request length) = [ status ])
        "advertised request length not rejected")
    lengths;
  List.iter
    (fun length ->
      check
        (exchange (chunk_request length) = [ 400 ])
        "advertised chunk length not rejected")
    [
      "0";
      "1";
      "1000";
      "1001";
      Printf.sprintf "%x" max_int;
      "4000000000000000";
      "7fffffffffffffff";
      "ffffffffffffffff";
      String.make 1000 'f';
    ];
  List.iter
    (fun bytes -> check (exchange bytes = [ 431 ]) "request header limit not enforced")
    [
      Bytes.of_string
        ("GET /" ^ String.make 2048 'a' ^ " HTTP/1.1\r\nHost: localhost\r\n\r\n");
      Bytes.of_string
        ("GET / HTTP/1.1\r\nHost: localhost\r\nX-Fuzz: " ^ String.make 4096 'a'
       ^ "\r\n\r\n");
    ];
  (* After a non-empty chunk, adding max_int must not wrap the typed diagnostic. *)
  let overflow =
    Bytes.of_string
      ("POST / HTTP/1.1\r\n\
        Host: localhost\r\n\
        Transfer-Encoding: chunked\r\n\
        \r\n\
        1\r\n\
        a\r\n" ^ Printf.sprintf "%x" max_int ^ "\r\n")
  in
  check (exchange overflow = [ 400 ]) "chunk length overflow not rejected"

(* Port of v1:test/http_fuzz/fuzz_h1_write.ml. Current writers serialize requests
   only; roundtrip uses the real request boundary, then H1_parse on its response. *)
let writer_properties random exchange =
  let url = H.Url.of_string "https://example.test:8443/fuzz/path?x=1" in
  let string_gen bound = G.map Bytes.to_string (bounded_bytes bound) in
  let safe_string bound =
    G.map
      (fun chars -> String.of_seq (List.to_seq chars))
      (G.list_size (G.int_range 0 bound) (G.map Char.chr (G.int_range 97 122)))
  in
  let headers gen = G.list_size (G.int_range 0 8) gen in
  let body =
    G.oneof_weighted
      [
        (1, G.pure H.H1_write.Empty);
        ( 3,
          G.map
            (fun chunks -> H.H1_write.Fixed chunks)
            (G.list_size (G.int_range 0 4) (bounded_bytes 128)) );
      ]
  in
  let valid =
    G.triple
      (G.oneof_list [ "GET"; "POST"; "PUT"; "PATCH" ])
      (headers
         (G.map2
            (fun name value -> ("X-Fuzz-" ^ name, value))
            (safe_string 16) (safe_string 128)))
      body
  in
  let arbitrary =
    G.triple (string_gen 16) (headers (G.pair (string_gen 32) (string_gen 128))) body
  in
  let generator =
    G.oneof_weighted
      [
        (3, G.map (fun input -> (true, input)) valid);
        (1, G.map (fun input -> (false, input)) arbitrary);
      ]
  in
  let print (valid, (method_, headers, body)) =
    let chunks = match body with H.H1_write.Empty -> [] | Fixed chunks -> chunks in
    Printf.sprintf "valid=%b method=%S headers=[%s] body=[%s]" valid method_
      (String.concat "; " (List.map (fun (n, v) -> Printf.sprintf "%S:%S" n v) headers))
      (String.concat "; " (List.map print_bytes chunks))
  in
  let property (valid, (method_, headers, body)) =
    let string_result = H.H1_write.to_string ~method_ ~url ~headers ~body in
    let pos = 7 in
    let bytes = Bytes.make (input_limit + pos) '\127' in
    let original = Bytes.copy bytes in
    let bytes_result =
      H.H1_write.write_to_bytes bytes ~pos ~method_ ~url ~headers ~body
    in
    let buffer = Buffer.create 512 in
    Buffer.add_string buffer "prefix:";
    let buffer_result = H.H1_write.write buffer ~method_ ~url ~headers ~body in
    (match (string_result, bytes_result, buffer_result) with
    | Ok wire, Ok next, Ok () ->
        check (next = pos + String.length wire) "bytes writer cursor differs";
        check (Bytes.sub_string bytes pos (next - pos) = wire) "bytes writer differs";
        check (Buffer.contents buffer = "prefix:" ^ wire) "buffer writer differs";
        check
          (Bytes.sub bytes 0 pos = Bytes.sub original 0 pos)
          "bytes writer clobbered prefix";
        check
          (Bytes.sub bytes next (Bytes.length bytes - next)
          = Bytes.sub original next (Bytes.length bytes - next))
          "bytes writer clobbered suffix";
        if valid then
          let payload =
            match body with
            | H.H1_write.Empty -> Bytes.empty
            | Fixed chunks -> Bytes.concat Bytes.empty chunks
          in
          check
            (exchange
               ~expected:(method_, "/fuzz/path?x=1", payload)
               (Bytes.of_string wire)
            = [ 204 ])
            "writer output rejected by request parser"
    | Error string_error, Error bytes_error, Error buffer_error ->
        check (not valid) "writers rejected valid generated request";
        List.iter
          (fun (error : H.Error.t) ->
            match error.kind with
            | Header_invalid { reason } ->
                check
                  (reason <> "" && error.method_ = method_
                  && error.uri = H.Url.to_string url)
                  "invalid typed writer rejection")
          [ string_error; bytes_error; buffer_error ];
        check
          (Buffer.contents buffer = "prefix:")
          "buffer changed before writer rejection";
        check (bytes = original) "bytes changed before writer rejection"
    | _ -> failwith "h1 writers disagree on acceptance");
    true
  in
  let name = "h1 writers agree or reject together; valid requests roundtrip" in
  Printf.printf "%s (500 cases)\n%!" name;
  QCheck2.Test.check_exn ~rand:random
    (QCheck2.Test.make ~name ~count:500 ~print generator property)

let corpus_directory () =
  let rec loop i =
    if i >= Array.length Sys.argv then "corpus"
    else if Sys.argv.(i) = "--corpus" then
      if i + 1 < Array.length Sys.argv then Sys.argv.(i + 1)
      else invalid_arg "--corpus: missing directory"
    else loop (i + 1)
  in
  loop 1

let run () =
  let random = Stress_support.random ~default:6060 () in
  Eio_main.run (fun env ->
      Eio.Time.with_timeout_exn env#clock 55.0 (fun () ->
          let load = load_corpus env#fs (corpus_directory ()) in
          let requests =
            load
              [ "h1-request/get.http"; "h1-request/post.http"; "h1-request/chunked.http" ]
          in
          let responses =
            load
              [
                "h1-response/empty.http";
                "h1-response/fixed.http";
                "h1-response/duplicate-length.http";
              ]
          in
          let ws =
            load
              [
                "ws/text.hex";
                "ws/masked-text.hex";
                "ws/continuation.hex";
                "ws/ping.hex";
                "ws/pong.hex";
                "ws/close.hex";
                "ws/binary-126.hex";
              ]
            |> List.map (fun (name, bytes) -> (name, hexadecimal (Bytes.to_string bytes)))
          in
          deterministic_responses responses;
          deterministic_ws ws;
          with_requests env (fun exchange ->
              deterministic_requests requests exchange;
              writer_properties random (fun ~expected bytes -> exchange ~expected bytes);
              run_property random "h1 response: mutated corpus and arbitrary bytes" 3000
                (fuzz_gen responses) (fun bytes -> ignore (response bytes));
              run_property random
                "ws: mutated corpus and arbitrary bytes, both masking modes" 3000
                (fuzz_gen ws) (fun bytes ->
                  ignore (websocket ~masked:false bytes);
                  ignore (websocket ~masked:true bytes));
              run_property random "h1 request: mutated corpus and arbitrary bytes" 800
                (fuzz_gen requests) (fun bytes -> ignore (exchange bytes));
              run_property random "h1 response: advertised lengths" 300
                (G.map decimal_response (G.oneof_list lengths))
                (fun bytes -> ignore (response bytes));
              run_property random "h1 request: advertised lengths" 100
                (G.map decimal_request (G.oneof_list lengths))
                (fun bytes -> ignore (exchange bytes)));
          Printf.printf
            "parser_fuzz: corpus truncations, boundaries and seeded properties passed\n%!"))

let () = run ()
