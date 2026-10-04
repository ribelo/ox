type tls = { ca_file : string option }

let tls ?ca_file () = { ca_file }

type t = T : Eio.Switch.t * 'n Eio.Net.t * 'c Eio.Time.clock * tls -> t
type response = { status : int; headers : (string * string) list; body : bytes }

type error =
  [ `Connect of string
  | `Tls of string
  | `Timeout
  | `Idle_timeout
  | `Protocol of string
  | `Body_too_large
  | `Closed ]

let create ~sw ~net ~clock ?(tls = tls ()) () = T (sw, net, clock, tls)

exception Http_failure of error

let reject error = raise (Http_failure error)
let protocol text = reject (`Protocol text)

let header name headers =
  List.find_map
    (fun (key, value) ->
      if String.equal (String.lowercase_ascii key) name then Some value else None)
    headers

let has_token needle value =
  String.split_on_char ',' (String.lowercase_ascii value)
  |> List.exists (fun token -> String.equal (String.trim token) needle)

type 'c reader = {
  flow : Eio.Flow.two_way_ty Eio.Resource.t;
  clock : 'c Eio.Time.clock;
  idle : Ox.Duration.t option;
  input : Cstruct.t;
  mutable pos : int;
  mutable available : int;
}

let refill r =
  let perform () =
    try Ok (Eio.Flow.single_read r.flow r.input) with End_of_file -> Error `Closed
  in
  let result =
    match r.idle with
    | None -> perform ()
    | Some delay -> (
        match
          Ox.Timeout.timeout ~clock:r.clock delay (fun () ->
              match perform () with Ok n -> Ok n | Error _ -> Error `Closed)
        with
        | Error `Timeout -> Error `Idle_timeout
        | Error `Closed -> Error `Closed
        | Ok n -> Ok n)
  in
  match result with
  | Ok n when n > 0 ->
      r.pos <- 0;
      r.available <- n
  | Ok _ | Error `Closed -> reject `Closed
  | Error `Idle_timeout -> reject `Idle_timeout

let available r = if r.pos = r.available then refill r

let take_byte r =
  available r;
  let c = Cstruct.get_char r.input r.pos in
  r.pos <- r.pos + 1;
  c

let read_line r =
  let buf = Buffer.create 64 in
  let rec loop () =
    if Buffer.length buf >= 32768 then protocol "HTTP line exceeds 32 KiB";
    let c = take_byte r in
    if c = '\n' then (
      let s = Buffer.contents buf in
      let n = String.length s in
      if n = 0 || s.[n - 1] <> '\r' then protocol "line missing CRLF";
      String.sub s 0 (n - 1))
    else (
      Buffer.add_char buf c;
      loop ())
  in
  loop ()

let read_exact r length =
  let dst = Bytes.create length in
  let rec loop pos =
    if pos < length then (
      available r;
      let count = min (length - pos) (r.available - r.pos) in
      Cstruct.blit_to_bytes r.input r.pos dst pos count;
      r.pos <- r.pos + count;
      loop (pos + count))
  in
  loop 0;
  dst

let read_response r ~method_ ~max_body_bytes =
  let head = Buffer.create 512 in
  let rec headers () =
    let line = read_line r in
    if Buffer.length head + String.length line + 2 > 32768 then
      protocol "response headers exceed 32 KiB";
    Buffer.add_string head line;
    Buffer.add_string head "\r\n";
    if line <> "" then headers ()
  in
  headers ();
  let raw_bytes = Bytes.of_string (Buffer.contents head) in
  let len = Bytes.length raw_bytes in
  let parsed = H1_parse.create_raw_response () in
  let raw_headers = H1_parse.create_raw_headers 256 in
  let code =
    H1_parse.parse_raw raw_bytes ~len ~max_header_bytes:32768 ~headers:raw_headers parsed
  in
  if code <> H1_parse.raw_ok && code <> H1_parse.raw_body_truncated then
    protocol
      (H1_parse.parse_error_to_string
         (H1_parse.raw_error raw_bytes parsed ~max_header_bytes:32768 code));
  let status = H1_parse.raw_status parsed in
  let headers = H1_parse.raw_headers_to_list raw_bytes raw_headers parsed in
  let body =
    if
      String.equal method_ "HEAD" || status = 204 || status = 304
      || (status >= 100 && status < 200)
    then Bytes.empty
    else
      match header "transfer-encoding" headers with
      | Some value ->
          if header "content-length" headers <> None then
            protocol "conflicting Content-Length and Transfer-Encoding";
          if not (String.equal (String.lowercase_ascii (String.trim value)) "chunked")
          then protocol "unsupported Transfer-Encoding";
          let result = Buffer.create (min max_body_bytes 4096) in
          let rec chunks () =
            let line = read_line r in
            let size_text =
              match String.index_opt line ';' with
              | None -> line
              | Some n -> String.sub line 0 n
            in
            let size =
              try int_of_string ("0x" ^ String.trim size_text)
              with Failure _ -> protocol "invalid chunk size"
            in
            if size < 0 then protocol "negative chunk size";
            if size = 0 then (
              let rec trailers () = if read_line r <> "" then trailers () in
              trailers ();
              Bytes.of_string (Buffer.contents result))
            else (
              if size > max_body_bytes - Buffer.length result then reject `Body_too_large;
              Buffer.add_bytes result (read_exact r size);
              if read_line r <> "" then protocol "invalid chunk terminator";
              chunks ())
          in
          chunks ()
      | None -> (
          match H1_parse.raw_content_length parsed with
          | Some length ->
              if length > max_body_bytes then reject `Body_too_large;
              read_exact r length
          | None ->
              let result = Buffer.create (min max_body_bytes 4096) in
              let rec until_close () =
                if r.pos = r.available then
                  try
                    refill r;
                    until_close ()
                  with Http_failure `Closed -> Bytes.of_string (Buffer.contents result)
                else
                  let count = r.available - r.pos in
                  if count > max_body_bytes - Buffer.length result then
                    reject `Body_too_large;
                  Buffer.add_string result
                    (Cstruct.to_string (Cstruct.sub r.input r.pos count));
                  r.pos <- r.available;
                  until_close ()
              in
              until_close ())
  in
  { status; headers; body }

let request (T (_sw, net, clock, tls)) ~method_ ~url ?(headers = []) ?body ?deadline
    ?response_idle ?(max_body_bytes = 1024 * 1024) () =
  if max_body_bytes < 0 then invalid_arg "Client.request: negative max_body_bytes";
  let perform () =
    match Url.parse url with
    | Error e -> Error (`Protocol (Url.parse_error_to_string e))
    | Ok target -> (
        let headers =
          ("Connection", "close")
          :: List.filter
               (fun (name, _) ->
                 not (String.equal (String.lowercase_ascii name) "connection"))
               headers
        in
        let body =
          match body with None -> H1_write.Empty | Some b -> H1_write.Fixed [ b ]
        in
        match H1_write.to_string ~method_ ~url:target ~headers ~body with
        | Error e -> (
            match e.Error.kind with
            | Error.Header_invalid { reason } -> Error (`Protocol reason))
        | Ok message -> (
            let phase = ref `Connect in
            try
              Eio.Switch.run (fun _request_sw ->
                  Eio.Net.with_tcp_connect net ~host:(Url.host target)
                    ~service:(string_of_int (Url.effective_port target))
                    (fun raw ->
                      phase := `Tls;
                      let flow : Eio.Flow.two_way_ty Eio.Resource.t =
                        match Url.scheme target with
                        | Url.Http -> (raw :> Eio.Flow.two_way_ty Eio.Resource.t)
                        | Url.Https ->
                            let ssl_ctx = Ox_http_tls_openssl.create_ctx () in
                            Option.iter
                              (Ox_http_tls_openssl.ctx_load_ca ssl_ctx)
                              tls.ca_file;
                            let host = Url.host target in
                            let hostname, ip =
                              try
                                ignore (Unix.inet_addr_of_string host);
                                (None, Some host)
                              with Failure _ -> (Some host, None)
                            in
                            let ssl =
                              Ox_http_tls_openssl.create_ssl ssl_ctx ~hostname ~ip
                                ~alpn_protocols:[ "http/1.1" ]
                            in
                            (Tls_flow.create ~raw:(raw :> Tls_flow.ty Eio.Resource.t) ~ssl
                              :> Eio.Flow.two_way_ty Eio.Resource.t)
                      in
                      phase := `Closed;
                      Eio.Flow.copy_string message flow;
                      let reader =
                        {
                          flow;
                          clock;
                          idle = response_idle;
                          input = Cstruct.create 16384;
                          pos = 0;
                          available = 0;
                        }
                      in
                      read_response reader ~method_ ~max_body_bytes))
              |> fun response -> Ok response
            with
            | Http_failure error -> Error error
            | exn when Option.is_some (Tls_flow.failure_message exn) ->
                Error (`Tls (Option.get (Tls_flow.failure_message exn)))
            | Failure why when !phase = `Tls -> Error (`Tls why)
            | Eio.Io _ as e -> (
                match !phase with
                | `Connect -> Error (`Connect (Printexc.to_string e))
                | `Tls -> Error (`Tls (Printexc.to_string e))
                | _ -> Error `Closed)
            | End_of_file -> Error `Closed))
  in
  match deadline with
  | None -> perform ()
  | Some delay -> Ox.Timeout.timeout ~clock delay perform
