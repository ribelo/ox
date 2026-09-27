module C = Ws_codec
module Ssl = Eta_http_tls_openssl

type message = [ `Text of string | `Binary of bytes ]

type error =
  [ `Url of string
  | `Connect of string
  | `Tls of string
  | `Timeout
  | `Upgrade_failed of int * (string * string) list
  | `Protocol of string
  | `Message_too_large
  | `Closed of int * string ]

exception Failure of error

let fail e = raise (Failure e)

type t = {
  flow : Eio.Flow.two_way_ty Eio.Resource.t;
  shutdown : unit -> unit;
  lock : Eio.Mutex.t;
  mutable closed : bool;
  selected : string option;
  max_message_bytes : int;
}

let selected_protocol t = t.selected

let header name headers =
  let values =
    List.filter_map
      (fun (key, value) ->
        if String.equal (String.lowercase_ascii key) name then Some value else None)
      headers
  in
  match values with
  | [] -> None
  | [ value ] -> Some value
  | _ -> fail (`Protocol ("duplicate " ^ name ^ " upgrade header"))

let has_token needle value =
  String.split_on_char ',' (String.lowercase_ascii value)
  |> List.exists (fun token -> String.equal (String.trim token) needle)

let read_exact flow count =
  let data = Bytes.create count in
  let rec loop offset =
    if offset < count then (
      let slice = Cstruct.create (count - offset) in
      let n =
        try Eio.Flow.single_read flow slice
        with End_of_file -> fail (`Closed (1006, "unexpected EOF"))
      in
      if n <= 0 then fail (`Closed (1006, "unexpected EOF"));
      Cstruct.blit_to_bytes slice 0 data offset n;
      loop (offset + n))
  in
  loop 0;
  data

let read_head flow =
  let buf = Buffer.create 256 in
  let rec loop () =
    if Buffer.length buf >= 32768 then fail (`Protocol "upgrade headers exceed 32 KiB");
    let b = Bytes.get (read_exact flow 1) 0 in
    Buffer.add_char buf b;
    let s = Buffer.contents buf in
    let n = String.length s in
    if n >= 4 && String.sub s (n - 4) 4 = "\r\n\r\n" then s else loop ()
  in
  loop ()

let parse_head text =
  let lines = String.split_on_char '\n' text |> List.map String.trim in
  match lines with
  | status :: rest ->
      let fields = String.split_on_char ' ' status |> List.filter (( <> ) "") in
      let code =
        match fields with "HTTP/1.1" :: code :: _ -> int_of_string_opt code | _ -> None
      in
      let code =
        match code with
        | Some code -> code
        | None -> fail (`Protocol "invalid HTTP upgrade status")
      in
      let headers =
        List.filter_map
          (fun line ->
            if line = "" then None
            else
              match String.index_opt line ':' with
              | None -> fail (`Protocol "malformed upgrade header")
              | Some idx ->
                  Some
                    ( String.trim (String.sub line 0 idx),
                      String.trim
                        (String.sub line (idx + 1) (String.length line - idx - 1)) ))
          rest
      in
      (code, headers)
  | _ -> fail (`Protocol "empty HTTP upgrade response")

let validate_header (name, value) =
  let legal_name =
    String.length name > 0
    && String.for_all
         (fun c ->
           let n = Char.code c in
           n >= 33 && n <= 126 && not (String.contains "()<>@,;:\"/[]?={} " c))
         name
  in
  let legal_value =
    String.for_all
      (fun c ->
        let n = Char.code c in
        n <> 13 && n <> 10 && n <> 0 && (n >= 32 || n = 9))
      value
  in
  if not (legal_name && legal_value) then fail (`Protocol "invalid request header");
  if
    List.mem (String.lowercase_ascii name)
      [
        "host";
        "connection";
        "upgrade";
        "sec-websocket-version";
        "sec-websocket-key";
        "sec-websocket-protocol";
      ]
  then fail (`Protocol "reserved upgrade request header")

let parse_url input =
  let secure, http_url =
    if String.starts_with ~prefix:"wss://" input then
      (true, "https://" ^ String.sub input 6 (String.length input - 6))
    else if String.starts_with ~prefix:"ws://" input then
      (false, "http://" ^ String.sub input 5 (String.length input - 5))
    else fail (`Url "expected ws:// or wss://")
  in
  match Url.parse http_url with
  | Ok url -> (secure, url)
  | Error e -> fail (`Url (Url.parse_error_to_string e))

let create_tls raw host ca_file =
  let ctx = Ssl.create_ctx () in
  Option.iter (Ssl.ctx_load_ca ctx) ca_file;
  let hostname, ip =
    try
      ignore (Unix.inet_addr_of_string host);
      (None, Some host)
    with Stdlib.Failure _ -> (Some host, None)
  in
  let ssl = Ssl.create_ssl ctx ~hostname ~ip ~alpn_protocols:[ "http/1.1" ] in
  Tls_flow.create ~raw:(raw :> Eio.Flow.two_way_ty Eio.Resource.t) ~ssl

let connect ~sw ~net ~clock ?ca_file ?(headers = []) ?(protocols = [])
    ?(establishment_timeout = Eta.Duration.seconds 10) ?(max_message_bytes = 1_048_576)
    input =
  if max_message_bytes < 0 then invalid_arg "Ws_client.connect: negative message limit";
  let perform () =
    let stage = ref `Connect in
    let cleanup = ref (fun () -> ()) in
    let established = ref false in
    Fun.protect
      ~finally:(fun () -> if not !established then !cleanup ())
      (fun () ->
        try
          List.iter validate_header headers;
          List.iter
            (fun p ->
              if
                p = ""
                || String.exists
                     (fun c ->
                       Char.code c < 33
                       || Char.code c > 126
                       || String.contains "()<>@,;:\"/[]?={} " c)
                     p
              then fail (`Protocol "invalid subprotocol"))
            protocols;
          let secure, url = parse_url input in
          let addresses =
            Eio.Net.getaddrinfo_stream
              ~service:(string_of_int (Url.effective_port url))
              net (Url.host url)
          in
          let rec dial last = function
            | [] ->
                fail
                  (`Connect
                     (match last with
                     | Some reason -> reason
                     | None -> "DNS returned no addresses"))
            | addr :: rest -> (
                try Eio.Net.connect ~sw net addr
                with Eio.Io _ as exn -> dial (Some (Printexc.to_string exn)) rest)
          in
          let raw = dial None addresses in
          (cleanup := fun () -> Eio.Flow.close raw);
          let flow =
            if secure then (
              stage := `Tls;
              create_tls raw (Url.host url) ca_file)
            else (raw :> Eio.Flow.two_way_ty Eio.Resource.t)
          in
          stage := `Upgrade;
          let key = C.key_of_nonce (Ssl.random_bytes 16) in
          let buf = Buffer.create 512 in
          Buffer.add_string buf ("GET " ^ Url.origin_form url ^ " HTTP/1.1\r\n");
          let add (k, v) = Buffer.add_string buf (k ^ ": " ^ v ^ "\r\n") in
          List.iter add
            [
              ("Host", Url.authority url);
              ("Connection", "Upgrade");
              ("Upgrade", "websocket");
              ("Sec-WebSocket-Version", "13");
              ("Sec-WebSocket-Key", key);
            ];
          if protocols <> [] then
            add ("Sec-WebSocket-Protocol", String.concat ", " protocols);
          List.iter add headers;
          Buffer.add_string buf "\r\n";
          Eio.Flow.copy_string (Buffer.contents buf) flow;
          let status, response = read_head flow |> parse_head in
          if status <> 101 then fail (`Upgrade_failed (status, response));
          if
            not
              (match header "upgrade" response with
              | Some v -> String.equal (String.lowercase_ascii v) "websocket"
              | None -> false)
          then fail (`Protocol "missing Upgrade: websocket");
          if
            not
              (match header "connection" response with
              | Some v -> has_token "upgrade" v
              | None -> false)
          then fail (`Protocol "missing Connection: Upgrade");
          if header "sec-websocket-extensions" response <> None then
            fail (`Protocol "unsupported WebSocket extensions");
          if
            header "sec-websocket-accept" response
            <> Some (C.accept_key ~sha1:Ssl.sha1 key)
          then fail (`Protocol "invalid Sec-WebSocket-Accept");
          let selected = header "sec-websocket-protocol" response in
          (match selected with
          | None -> ()
          | Some p when List.mem p protocols -> ()
          | Some _ -> fail (`Protocol "unexpected WebSocket subprotocol"));
          established := true;
          Ok
            {
              flow;
              shutdown = (fun () -> Eio.Flow.close raw);
              lock = Eio.Mutex.create ();
              closed = false;
              selected;
              max_message_bytes;
            }
        with
        | Failure error -> Error error
        | Tls_flow.Tls_failure detail -> Error (`Tls detail)
        | Stdlib.Failure detail when !stage = `Tls -> Error (`Tls detail)
        | Eio.Io _ as exn ->
            Error
              (match !stage with
              | `Tls -> `Tls (Printexc.to_string exn)
              | `Connect -> `Connect (Printexc.to_string exn)
              | `Upgrade -> `Connect (Printexc.to_string exn))
        | End_of_file -> Error (`Closed (1006, "unexpected EOF")))
  in
  Eta.Timeout.timeout ~clock establishment_timeout perform

let writing t fn =
  try
    Eio.Mutex.use_ro t.lock (fun () ->
        if t.closed then Error (`Closed (1000, "closed")) else fn ())
  with
  | Tls_flow.Tls_failure s -> Error (`Tls s)
  | Eio.Io _ | End_of_file -> Error (`Closed (1006, "write failed"))

let send_frame t frame =
  writing t (fun () ->
      let mask = Ssl.random_bytes 4 in
      Eio.Flow.copy_string (Bytes.to_string (C.encode ~mask frame)) t.flow;
      Ok ())

let send_text t text =
  send_frame t { C.fin = true; opcode = Text; payload = Bytes.of_string text }

let send_binary t payload = send_frame t { C.fin = true; opcode = Binary; payload }

let close ?(code = 1000) ?(reason = "") t =
  if
    not
      (code = 1000
      || (code >= 1001 && code <= 1014 && code <> 1004 && code <> 1005 && code <> 1006)
      || (code >= 3000 && code <= 4999))
  then invalid_arg "Ws_client.close: invalid close code";
  if String.length reason > 123 then invalid_arg "Ws_client.close: reason too long";
  Eio.Mutex.use_ro t.lock (fun () ->
      if t.closed then Ok ()
      else (
        t.closed <- true;
        let payload = Bytes.create (2 + String.length reason) in
        Bytes.set_int16_be payload 0 code;
        Bytes.blit_string reason 0 payload 2 (String.length reason);
        let result =
          try
            Eio.Flow.copy_string
              (Bytes.to_string
                 (C.encode ~mask:(Ssl.random_bytes 4)
                    { C.fin = true; opcode = Close; payload }))
              t.flow;
            Ok ()
          with Eio.Io _ | End_of_file | Tls_flow.Tls_failure _ ->
            Error (`Closed (1006, "close failed"))
        in
        t.shutdown ();
        result))

let read_frame t =
  let h = read_exact t.flow 2 in
  let code = Char.code (Bytes.get h 1) in
  let n = code land 127 in
  let ext = if n = 126 then 2 else if n = 127 then 8 else 0 in
  let length_bytes = read_exact t.flow ext in
  let length =
    if ext = 0 then Int64.of_int n
    else if ext = 2 then Int64.of_int (Bytes.get_uint16_be length_bytes 0)
    else Bytes.get_int64_be length_bytes 0
  in
  if Int64.compare length (Int64.of_int t.max_message_bytes) > 0 then
    fail `Message_too_large;
  if code land 128 <> 0 then fail (`Protocol "server frame is masked");
  let payload = read_exact t.flow (Int64.to_int length) in
  let bytes = Bytes.concat Bytes.empty [ h; length_bytes; payload ] in
  match C.decode bytes with
  | Ok (frame, _) -> frame
  | Error e -> fail (`Protocol (C.parse_error_to_string e))

let valid_utf8 text =
  let n = String.length text in
  let byte i = Char.code text.[i] in
  let cont b = b land 0xc0 = 0x80 in
  let rec go i =
    if i = n then true
    else
      let a = byte i in
      if a < 0x80 then go (i + 1)
      else if a < 0xc2 || a > 0xf4 then false
      else if a < 0xe0 then i + 1 < n && cont (byte (i + 1)) && go (i + 2)
      else if a < 0xf0 then
        i + 2 < n
        && (let b = byte (i + 1) in
            cont b && (a <> 0xe0 || b >= 0xa0) && (a <> 0xed || b < 0xa0))
        && cont (byte (i + 2))
        && go (i + 3)
      else
        i + 3 < n
        && (let b = byte (i + 1) in
            cont b && (a <> 0xf0 || b >= 0x90) && (a <> 0xf4 || b < 0x90))
        && cont (byte (i + 2))
        && cont (byte (i + 3))
        && go (i + 4)
  in
  go 0

let receive t =
  try
    if t.closed then fail (`Closed (1000, "closed"));
    let output = Buffer.create 256 in
    let rec loop kind pings =
      let frame = read_frame t in
      match frame.C.opcode with
      | Ping -> (
          if pings >= 32 then fail (`Protocol "too many consecutive pings");
          match send_frame t { C.fin = true; opcode = Pong; payload = frame.payload } with
          | Error e -> fail e
          | Ok () -> loop kind (pings + 1))
      | Pong -> loop kind (pings + 1)
      | Close ->
          let code, reason =
            if Bytes.length frame.payload < 2 then (1000, "")
            else
              ( Bytes.get_uint16_be frame.payload 0,
                Bytes.sub_string frame.payload 2 (Bytes.length frame.payload - 2) )
          in
          if not (valid_utf8 reason) then fail (`Protocol "invalid close reason UTF-8");
          ignore (close ~code:(if code = 1000 then 1000 else code) t);
          fail (`Closed (code, reason))
      | (Text | Binary | Continuation) as op ->
          let kind =
            match (op, kind) with
            | Continuation, None -> fail (`Protocol "unexpected continuation")
            | Continuation, Some existing -> existing
            | (Text | Binary), Some _ ->
                fail (`Protocol "new message during fragmentation")
            | Text, None -> `Text
            | Binary, None -> `Binary
            | _ -> assert false
          in
          if Bytes.length frame.payload > t.max_message_bytes - Buffer.length output then
            fail `Message_too_large;
          Buffer.add_bytes output frame.payload;
          if frame.fin then (
            let data = Buffer.contents output in
            if kind = `Text && not (valid_utf8 data) then
              fail (`Protocol "invalid text UTF-8");
            Ok (if kind = `Text then `Text data else `Binary (Bytes.of_string data)))
          else loop (Some kind) 0
    in
    loop None 0
  with
  | Failure e ->
      if not t.closed then (
        t.closed <- true;
        t.shutdown ());
      Error e
  | Tls_flow.Tls_failure s ->
      if not t.closed then (
        t.closed <- true;
        t.shutdown ());
      Error (`Tls s)
  | Eio.Io _ | End_of_file ->
      if not t.closed then (
        t.closed <- true;
        t.shutdown ());
      Error (`Closed (1006, "read failed"))
