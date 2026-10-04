type tls = { ca_file : string option }

let tls ?ca_file () = { ca_file }

type t = T : Eio.Switch.t * 'n Eio.Net.t * 'c Eio.Time.clock * tls -> t
type body = [ `Read of bytes | `Skipped ]
type response = { status : int; headers : (string * string) list; body : body }

type body_reason =
  [ `Truncated
  | `Malformed of string
  | `Too_large
  | `Idle_timeout
  | `Timeout
  | `Tls of string
  | `Closed
  | `Connect of string ]

type body_failure = {
  status : int;
  headers : (string * string) list;
  reason : body_reason;
}

type error =
  [ `Connect of string
  | `Tls of string
  | `Timeout
  | `Idle_timeout
  | `Protocol of string
  | `Body of body_failure
  | `Closed ]

let create ~sw ~net ~clock ?(tls = tls ()) () = T (sw, net, clock, tls)

(* Private parser/IO escape, caught within the request fiber, never around caller code. *)
type failure =
  [ `Connect of string
  | `Tls of string
  | `Idle_timeout
  | `Protocol of string
  | `Too_large
  | `Truncated
  | `Closed ]

exception Http_failure of failure

let reject error = raise (Http_failure error)
let protocol text = reject (`Protocol text)
let framing_budget = 32768

(* Only the IO call belongs inside this handler; in particular [on_head] does not. *)
let io ~on_error f =
  try f () with
  | End_of_file -> reject `Truncated
  | Eio.Io _ as exn -> reject (on_error (Printexc.to_string exn))
  | exn when Option.is_some (Tls_flow.failure_message exn) ->
      reject (`Tls (Option.get (Tls_flow.failure_message exn)))

let header name headers =
  List.find_map
    (fun (key, value) ->
      if String.equal (String.lowercase_ascii key) name then Some value else None)
    headers

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
    Ok (io ~on_error:(fun _ -> `Closed) (fun () -> Eio.Flow.single_read r.flow r.input))
  in
  let result =
    match r.idle with
    | None -> perform ()
    | Some delay -> (
        match Ox.Timeout.timeout ~clock:r.clock delay perform with
        | Error `Timeout -> Error `Idle_timeout
        | Ok n -> Ok n)
  in
  match result with
  | Ok n when n > 0 ->
      r.pos <- 0;
      r.available <- n
  | Ok _ -> reject `Truncated
  | Error `Idle_timeout -> reject `Idle_timeout

let available r = if r.pos = r.available then refill r

let take_byte r =
  available r;
  let c = Cstruct.get_char r.input r.pos in
  r.pos <- r.pos + 1;
  c

let read_line ?budget r =
  let buf = Buffer.create 64 in
  let rec loop () =
    if Buffer.length buf >= framing_budget then protocol "HTTP line exceeds 32 KiB";
    Option.iter
      (fun left ->
        if !left = 0 then protocol "HTTP framing section exceeds 32 KiB";
        decr left)
      budget;
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

let read_head r informational_bytes =
  let head = Buffer.create 512 in
  let budget = ref framing_budget in
  let status_line = read_line ~budget r in
  Buffer.add_string head (status_line ^ "\r\n");
  let status_bytes = Bytes.of_string (status_line ^ "\r\n\r\n") in
  let status_raw = H1_parse.create_raw_response () in
  let status_headers = H1_parse.create_raw_headers 1 in
  let status_code =
    H1_parse.parse_raw status_bytes ~len:(Bytes.length status_bytes)
      ~max_header_bytes:framing_budget ~headers:status_headers status_raw
  in
  if status_code <> H1_parse.raw_ok then protocol "invalid response status line";
  let status = H1_parse.raw_status status_raw in
  if status = 101 then protocol "101 Switching Protocols is unsupported";
  if status >= 100 && status < 200 then (
    let remaining = framing_budget - informational_bytes - Buffer.length head in
    if remaining < 0 then protocol "informational response heads exceed cumulative 32 KiB";
    budget := min !budget remaining);
  let rec lines () =
    let line = read_line ~budget r in
    Buffer.add_string head line;
    Buffer.add_string head "\r\n";
    if line <> "" then lines ()
  in
  lines ();
  let raw_bytes = Bytes.of_string (Buffer.contents head) in
  let len = Bytes.length raw_bytes in
  let parsed = H1_parse.create_raw_response () in
  let raw_headers = H1_parse.create_raw_headers 256 in
  let code =
    H1_parse.parse_raw raw_bytes ~len ~max_header_bytes:framing_budget
      ~headers:raw_headers parsed
  in
  if code <> H1_parse.raw_ok && code <> H1_parse.raw_body_truncated then
    protocol
      (H1_parse.parse_error_to_string
         (H1_parse.raw_error raw_bytes parsed ~max_header_bytes:framing_budget code));
  ( H1_parse.raw_status parsed,
    H1_parse.raw_headers_to_list raw_bytes raw_headers parsed,
    H1_parse.raw_content_length parsed,
    len )

let read_final_head r =
  let rec next informational_bytes =
    let status, headers, length, bytes = read_head r informational_bytes in
    if status = 101 then protocol "101 Switching Protocols is unsupported";
    if status >= 100 && status < 200 then (
      if bytes > framing_budget - informational_bytes then
        protocol "informational response heads exceed cumulative 32 KiB";
      next (informational_bytes + bytes))
    else (status, headers, length)
  in
  next 0

let read_body r ~method_ ~status ~headers ~length ~max_body_bytes =
  if String.equal method_ "HEAD" || status = 204 || status = 304 then Bytes.empty
  else
    match header "transfer-encoding" headers with
    | Some value ->
        if header "content-length" headers <> None then
          protocol "conflicting Content-Length and Transfer-Encoding";
        if not (String.equal (String.lowercase_ascii (String.trim value)) "chunked") then
          protocol "unsupported Transfer-Encoding";
        let result = Buffer.create (min max_body_bytes 4096) in
        let rec chunks () =
          let line = read_line r in
          let size_text =
            match String.index_opt line ';' with
            | None -> line
            | Some n -> String.sub line 0 n
          in
          (* [int_of_string] accepts signs and separators, which are not chunk digits. *)
          if
            size_text = ""
            || not
                 (String.for_all
                    (function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false)
                    size_text)
          then protocol "invalid chunk size";
          let size =
            try int_of_string ("0x" ^ size_text)
            with Failure _ -> protocol "invalid chunk size"
          in
          if size < 0 then protocol "negative chunk size";
          if size = 0 then (
            let budget = ref framing_budget in
            let rec trailers () =
              let line = read_line ~budget r in
              if line <> "" then (
                (match String.index_opt line ':' with
                | Some n when n > 0 ->
                    let name = String.sub line 0 n in
                    let value = String.sub line (n + 1) (String.length line - n - 1) in
                    let token = function
                      | 'a' .. 'z'
                      | 'A' .. 'Z'
                      | '0' .. '9'
                      | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^'
                      | '_' | '`' | '|' | '~' ->
                          true
                      | _ -> false
                    in
                    if
                      (not (String.for_all token name))
                      || not
                           (String.for_all
                              (fun c ->
                                c = '\t' || (Char.code c >= 32 && Char.code c <> 127))
                              value)
                    then protocol "invalid trailer field"
                | _ -> protocol "invalid trailer field");
                trailers ())
            in
            trailers ();
            Bytes.of_string (Buffer.contents result))
          else (
            if size > max_body_bytes - Buffer.length result then reject `Too_large;
            Buffer.add_bytes result (read_exact r size);
            if read_line r <> "" then protocol "invalid chunk terminator";
            chunks ())
        in
        chunks ()
    | None -> (
        match length with
        | Some length ->
            if length > max_body_bytes then reject `Too_large;
            read_exact r length
        | None ->
            let result = Buffer.create (min max_body_bytes 4096) in
            let rec until_close () =
              if r.pos = r.available then
                match refill r with
                | () -> until_close ()
                | exception Http_failure `Truncated ->
                    Bytes.of_string (Buffer.contents result)
              else
                let count = r.available - r.pos in
                if count > max_body_bytes - Buffer.length result then reject `Too_large;
                Buffer.add_string result
                  (Cstruct.to_string (Cstruct.sub r.input r.pos count));
                r.pos <- r.available;
                until_close ()
            in
            until_close ())

let pre_head f =
  try Ok (f ()) with
  | Http_failure (`Truncated | `Closed) -> Error `Closed
  | Http_failure `Too_large -> Error (`Protocol "unexpected payload before final head")
  | Http_failure ((`Connect _ | `Tls _ | `Idle_timeout | `Protocol _) as error) ->
      Error error

let body_reason : failure -> body_reason = function
  | `Protocol why -> `Malformed why
  | (`Truncated | `Too_large | `Idle_timeout | `Tls _ | `Closed | `Connect _) as reason ->
      reason

let connect ~sw net target =
  let addresses =
    io
      ~on_error:(fun why -> `Connect why)
      (fun () ->
        Eio.Net.getaddrinfo_stream net
          ~service:(string_of_int (Url.effective_port target))
          (Url.host target))
  in
  let rec next = function
    | [] -> reject (`Connect "no TCP address")
    | address :: rest -> (
        match
          io
            ~on_error:(fun why -> `Connect why)
            (fun () -> Eio.Net.connect ~sw net address)
        with
        | raw -> raw
        | exception Http_failure (`Connect _) when rest <> [] -> next rest)
  in
  next addresses

let secure raw target tls =
  match Url.scheme target with
  | Url.Http -> (raw :> Tls_flow.ty Eio.Resource.t)
  | Url.Https -> (
      let make () =
        let ssl_ctx = Ox_http_tls_openssl.create_ctx () in
        Option.iter (Ox_http_tls_openssl.ctx_load_ca ssl_ctx) tls.ca_file;
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
          :> Tls_flow.ty Eio.Resource.t)
      in
      try io ~on_error:(fun why -> `Tls why) make with Failure why -> reject (`Tls why))

let request (T (_sw, net, clock, tls)) ~method_ ~url ?(headers = []) ?body ?deadline
    ?response_idle ?(max_body_bytes = 1024 * 1024)
    ?(on_head = fun ~status:_ ~headers:_ -> `Read) () =
  if max_body_bytes < 0 then invalid_arg "Client.request: negative max_body_bytes";
  (* Written before the policy runs; the deadline's losing fiber is joined before it is inspected. *)
  let final_head = ref None in
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
        | Ok message ->
            Eio.Switch.run (fun request_sw ->
                match
                  pre_head (fun () ->
                      let raw = connect ~sw:request_sw net target in
                      let flow = secure raw target tls in
                      (match Url.scheme target with
                      | Url.Http -> ()
                      | Url.Https ->
                          Eio.Switch.on_release request_sw (fun () ->
                              try Eio.Resource.close flow with
                              | Eio.Io _ | End_of_file -> ()
                              | exn when Option.is_some (Tls_flow.failure_message exn) ->
                                  ()));
                      io
                        ~on_error:(fun _ -> `Closed)
                        (fun () -> Eio.Flow.copy_string message flow);
                      let reader =
                        {
                          flow :> Eio.Flow.two_way_ty Eio.Resource.t;
                          clock;
                          idle = response_idle;
                          input = Cstruct.create 16384;
                          pos = 0;
                          available = 0;
                        }
                      in
                      (reader, read_final_head reader))
                with
                | Error error -> Error error
                | Ok (reader, (status, headers, length)) -> (
                    final_head := Some (status, headers);
                    match on_head ~status ~headers with
                    | `Skip -> Ok { status; headers; body = `Skipped }
                    | `Read -> (
                        match
                          read_body reader ~method_ ~status ~headers ~length
                            ~max_body_bytes
                        with
                        | body -> Ok { status; headers; body = `Read body }
                        | exception Http_failure reason ->
                            Error (`Body { status; headers; reason = body_reason reason })
                        ))))
  in
  match deadline with
  | None -> perform ()
  | Some delay -> (
      match Ox.Timeout.timeout ~clock delay perform with
      | Error `Timeout -> (
          match !final_head with
          | None -> Error `Timeout
          | Some (status, headers) -> Error (`Body { status; headers; reason = `Timeout })
          )
      | result -> result)
