(* The HTTP/1 connection is intentionally direct-style: a single fiber owns each
   request body, parser buffer, response, and the next request on that socket. *)
module Error = struct
  type kind =
    | Bad_request of { message : string }
    | Request_body_too_large of { limit : int; length : int }
    | Handler_failed of { message : string }

  type t = { method_ : string; target : string; kind : kind }

  let make ~method_ ~target kind = { method_; target; kind }

  let pp fmt t =
    let text =
      match t.kind with
      | Bad_request { message } | Handler_failed { message } -> message
      | Request_body_too_large { limit; length } ->
          Printf.sprintf "body length %d exceeds %d" length limit
    in
    Format.fprintf fmt "%s %s: %s" t.method_ t.target text
end

exception Invalid_request of int * string
exception Request_limit of int * int

module Body = struct
  type t = {
    next : unit -> (bytes option, Error.t) result;
    mutable done_ : bool;
    mutable active : bool;
  }

  let empty () = { next = (fun () -> Ok None); done_ = true; active = false }
  let of_reader next = { next; done_ = false; active = false }

  let read t =
    if t.active then
      Error
        (Error.make ~method_:"*" ~target:"*"
           (Bad_request { message = "concurrent body read" }))
    else if t.done_ then Ok None
    else (
      t.active <- true;
      Fun.protect
        ~finally:(fun () -> t.active <- false)
        (fun () ->
          try
            match t.next () with
            | Ok None as value ->
                t.done_ <- true;
                value
            | result -> result
          with
          | Request_limit (limit, length) ->
              Error
                (Error.make ~method_:"*" ~target:"*"
                   (Request_body_too_large { limit; length }))
          | Invalid_request (_, message) ->
              Error (Error.make ~method_:"*" ~target:"*" (Bad_request { message }))
          | End_of_file ->
              Error
                (Error.make ~method_:"*" ~target:"*"
                   (Bad_request { message = "truncated request body" }))))

  let read_all ?(max_bytes = 1024 * 1024) t =
    if max_bytes < 0 then invalid_arg "Server.Body.read_all: negative max_bytes";
    let buffer = Buffer.create (min max_bytes 4096) in
    let rec loop () =
      match read t with
      | Error _ as error -> error
      | Ok None -> Ok (Bytes.of_string (Buffer.contents buffer))
      | Ok (Some part) ->
          let length = Buffer.length buffer + Bytes.length part in
          if length > max_bytes then
            Error
              (Error.make ~method_:"*" ~target:"*"
                 (Request_body_too_large { limit = max_bytes; length }))
          else (
            Buffer.add_bytes buffer part;
            loop ())
    in
    loop ()

  let rec discard t =
    match read t with Ok (Some _) -> discard t | Ok None -> Ok () | Error _ as e -> e
end

module Request = struct
  type peer = { address : string option; port : int option }

  type t = {
    id : string Lazy.t;
    version : Version.t;
    scheme : string;
    authority : string option;
    method_ : string;
    target : string;
    path : string;
    query : string option;
    headers : Header.t;
    body : Body.t;
    trailers : unit -> (Header.t, Error.t) result;
    peer : peer;
    tls : bool;
    alpn_protocol : string option;
    stream_id : int option;
    connection_id : string;
  }

  let split_target target =
    match String.index_opt target '?' with
    | None -> (target, None)
    | Some pos ->
        ( String.sub target 0 pos,
          Some (String.sub target (pos + 1) (String.length target - pos - 1)) )

  let header name t = Header.get name t.headers
  let body t = t.body
end

module Response = struct
  module Body = struct
    type stream = {
      length : int option;
      read : unit -> (bytes option, Error.t) result;
      release : unit -> unit;
    }

    type t = Empty | Fixed of bytes list | Stream of stream

    let empty = Empty
    let fixed xs = Fixed (List.map Bytes.copy xs)
    let string s = Fixed [ Bytes.of_string s ]

    let stream ?length ?(release = fun () -> ()) read =
      (match length with
      | Some n when n < 0 -> invalid_arg "negative stream length"
      | _ -> ());
      Stream { length; read; release }
  end

  type t = {
    status : int;
    headers : Header.t;
    body : Body.t;
    trailers : unit -> (Header.t, Error.t) result;
  }

  let make ?(headers = Header.empty) ?(trailers = fun () -> Ok Header.empty) ~status ~body
      () =
    if status < 200 || status > 599 then
      invalid_arg "Server.Response.make: invalid status";
    (match Header.validate headers with
    | Some _ -> invalid_arg "Server.Response.make: invalid headers"
    | None -> ());
    { status; headers; body; trailers }

  let empty ?headers ~status () = make ?headers ~status ~body:Body.Empty ()
  let text ?headers ?(status = 200) s = make ?headers ~status ~body:(Body.string s) ()
  let status t = t.status
  let headers t = t.headers
  let body t = t.body
  let trailers t = t.trailers
end

type handler = Request.t -> (Response.t, Error.t) result

module Handler = struct
  let of_sync f request = Ok (f request)
  let of_result f = f
  let route_not_found _ = Ok (Response.text ~status:404 "not found\n")

  let default_error_response e =
    let status =
      match e.Error.kind with
      | Bad_request _ -> 400
      | Request_body_too_large _ -> 413
      | Handler_failed _ -> 500
    in
    Response.text ~status (Format.asprintf "%a\n" Error.pp e)

  let with_default_error_response f request =
    match f request with
    | Ok _ as result -> result
    | Error e -> Ok (default_error_response e)
end

module Config = struct
  type t = {
    max_request_line_bytes : int;
    max_request_header_bytes : int;
    max_request_headers : int;
    max_request_body_bytes : int;
    max_response_header_bytes : int;
  }

  let default =
    {
      max_request_line_bytes = 8192;
      max_request_header_bytes = 32768;
      max_request_headers = 256;
      max_request_body_bytes = 1024 * 1024;
      max_response_header_bytes = 32768;
    }
end

let invalid status message = raise (Invalid_request (status, message))

let has_token token value =
  String.split_on_char ',' (String.lowercase_ascii value)
  |> List.exists (fun s -> String.equal (String.trim s) token)

type input = {
  flow : Eio.Flow.two_way_ty Eio.Resource.t;
  scratch : Cstruct.t;
  mutable pos : int;
  mutable len : int;
}

let refill r =
  let n = Eio.Flow.single_read r.flow r.scratch in
  r.pos <- 0;
  r.len <- n

let next_byte r =
  if r.pos = r.len then refill r;
  let ch = Cstruct.get_char r.scratch r.pos in
  r.pos <- r.pos + 1;
  ch

let line r ~limit =
  let b = Buffer.create 64 in
  let rec loop () =
    if Buffer.length b >= limit then invalid 431 "HTTP line too long";
    let c = next_byte r in
    if c = '\n' then (
      let text = Buffer.contents b in
      let n = String.length text in
      if n = 0 || text.[n - 1] <> '\r' then invalid 400 "HTTP line missing CRLF";
      String.sub text 0 (n - 1))
    else (
      Buffer.add_char b c;
      loop ())
  in
  loop ()

let take r count =
  let bytes = Bytes.create count in
  let rec loop offset =
    if offset < count then (
      if r.pos = r.len then refill r;
      let n = min (count - offset) (r.len - r.pos) in
      Cstruct.blit_to_bytes r.scratch r.pos bytes offset n;
      r.pos <- r.pos + n;
      loop (offset + n))
  in
  loop 0;
  bytes

let header name headers = Header.get name headers

let parse_head r config =
  let first = line r ~limit:config.Config.max_request_line_bytes in
  match String.split_on_char ' ' first with
  | [ method_; target; version ]
    when Header.validate_name method_ = None
         && String.length target > 0
         && target.[0] = '/' ->
      let version =
        match version with
        | "HTTP/1.1" -> Version.H1_1
        | "HTTP/1.0" -> Version.H1_0
        | _ -> invalid 400 "unsupported HTTP version"
      in
      let rec headers acc bytes count =
        let text = line r ~limit:config.Config.max_request_header_bytes in
        let bytes = bytes + String.length text + 2 in
        if bytes > config.max_request_header_bytes || count > config.max_request_headers
        then invalid 431 "request headers too large";
        if text = "" then List.rev acc
        else
          match String.index_opt text ':' with
          | None -> invalid 400 "invalid header line"
          | Some pos ->
              let name = String.sub text 0 pos in
              let value =
                String.trim (String.sub text (pos + 1) (String.length text - pos - 1))
              in
              if not (Header.validate_header (name, value) = None) then
                invalid 400 "invalid header";
              headers ((name, value) :: acc) bytes (count + 1)
      in
      let headers = headers [] (String.length first + 2) 0 in
      let hosts = Header.get_all "host" headers in
      if List.length hosts > 1 then invalid 400 "duplicate Host";
      if version = Version.H1_1 && (hosts = [] || hosts = [ "" ]) then
        invalid 400 "missing Host";
      let lengths = Header.get_all "content-length" headers in
      let length =
        match lengths with
        | [] -> None
        | hd :: tl when List.for_all (String.equal hd) tl -> (
            match int_of_string_opt hd with
            | Some n
              when n >= 0
                   && String.length hd > 0
                   && String.for_all (function '0' .. '9' -> true | _ -> false) hd ->
                Some n
            | _ -> invalid 400 "invalid Content-Length")
        | _ -> invalid 400 "conflicting Content-Length"
      in
      let chunked =
        match Header.get_all "transfer-encoding" headers with
        | [] -> false
        | [ value ]
          when String.equal (String.lowercase_ascii (String.trim value)) "chunked" ->
            true
        | _ -> invalid 400 "unsupported Transfer-Encoding"
      in
      if chunked && length <> None then invalid 400 "conflicting body framing";
      if Option.value ~default:0 length > config.max_request_body_bytes then
        invalid 413 "request body too large";
      (method_, target, version, headers, length, chunked)
  | _ -> invalid 400 "invalid request line"

let request_body r config method_ target length chunked =
  let total = ref 0 in
  let fail_length size =
    Error
      (Error.make ~method_ ~target
         (Error.Request_body_too_large
            { limit = config.Config.max_request_body_bytes; length = size }))
  in
  if chunked then
    let remaining = ref 0 and ended = ref false in
    Body.of_reader (fun () ->
        if !ended then Ok None
        else (
          if !remaining = 0 then (
            let text = line r ~limit:config.max_request_line_bytes in
            let number =
              match String.index_opt text ';' with
              | None -> text
              | Some pos -> String.sub text 0 pos
            in
            let size =
              match int_of_string_opt ("0x" ^ String.trim number) with
              | Some n when n >= 0 -> n
              | _ -> invalid 400 "invalid chunk size"
            in
            if size > config.max_request_body_bytes - !total then
              raise (Request_limit (config.max_request_body_bytes, !total + size));
            if size = 0 then (
              let rec trailers bytes =
                let text = line r ~limit:config.max_request_header_bytes in
                if bytes + String.length text + 2 > config.max_request_header_bytes then
                  invalid 431 "trailers too large";
                if text <> "" then trailers (bytes + String.length text + 2)
              in
              trailers 0;
              ended := true)
            else remaining := size);
          if !ended then Ok None
          else
            let count = min !remaining 8192 in
            let bytes = take r count in
            remaining := !remaining - count;
            total := !total + count;
            if !remaining = 0 && line r ~limit:2 <> "" then
              invalid 400 "invalid chunk terminator";
            Ok (Some bytes)))
  else
    match length with
    | None | Some 0 -> Body.empty ()
    | Some count ->
        let left = ref count in
        Body.of_reader (fun () ->
            if !left = 0 then Ok None
            else
              let size = min !left 8192 in
              if !total + size > config.max_request_body_bytes then
                fail_length (!total + size)
              else
                let bytes = take r size in
                left := !left - size;
                total := !total + size;
                Ok (Some bytes))

let reason = function
  | 200 -> "OK"
  | 201 -> "Created"
  | 202 -> "Accepted"
  | 204 -> "No Content"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 408 -> "Request Timeout"
  | 413 -> "Content Too Large"
  | 417 -> "Expectation Failed"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 503 -> "Service Unavailable"
  | _ -> "Response"

let write_response flow config ~close ~head (response : Response.t) =
  let status = Response.status response in
  let no_body = status = 204 || status = 304 in
  let body = if no_body then Response.Body.Empty else Response.body response in
  let size =
    match body with
    | Empty -> Some 0
    | Fixed chunks ->
        Some (List.fold_left (fun n bytes -> n + Bytes.length bytes) 0 chunks)
    | Stream stream -> stream.length
  in
  let chunked = size = None && not close in
  let headers =
    Header.remove "transfer-encoding"
      (Header.remove "content-length" (Response.headers response))
  in
  let headers = ("connection", if close then "close" else "keep-alive") :: headers in
  let headers =
    match size with
    | Some n -> ("content-length", string_of_int n) :: headers
    | None when chunked -> ("transfer-encoding", "chunked") :: headers
    | None -> headers
  in
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "HTTP/1.1 %d %s\r\n" status (reason status));
  List.iter
    (fun (name, value) ->
      if not (Header.validate_header (name, value) = None) then
        invalid 500 "invalid response header";
      Buffer.add_string b name;
      Buffer.add_string b ": ";
      Buffer.add_string b value;
      Buffer.add_string b "\r\n")
    headers;
  Buffer.add_string b "\r\n";
  if Buffer.length b > config.Config.max_response_header_bytes then
    invalid 500 "response headers too large";
  Eio.Flow.copy_string (Buffer.contents b) flow;
  let write_bytes bytes =
    if not head then (
      if chunked then
        Eio.Flow.copy_string (Printf.sprintf "%x\r\n" (Bytes.length bytes)) flow;
      if Bytes.length bytes > 0 then Eio.Flow.write flow [ Cstruct.of_bytes bytes ];
      if chunked then Eio.Flow.copy_string "\r\n" flow)
  in
  (match body with
  | Empty -> ()
  | Fixed chunks -> List.iter write_bytes chunks
  | Stream stream when head || no_body -> stream.release ()
  | Stream stream ->
      Fun.protect ~finally:stream.release (fun () ->
          let sent = ref 0 in
          let rec loop () =
            match stream.read () with
            | Error error -> invalid 500 (Format.asprintf "%a" Error.pp error)
            | Ok None -> (
                match size with
                | Some n when n <> !sent -> invalid 500 "stream length mismatch"
                | _ -> ())
            | Ok (Some bytes) ->
                sent := !sent + Bytes.length bytes;
                (match size with
                | Some n when !sent > n -> invalid 500 "stream length mismatch"
                | _ -> ());
                if Bytes.length bytes > 0 then write_bytes bytes;
                loop ()
          in
          loop ()));
  if chunked && not head then Eio.Flow.copy_string "0\r\n\r\n" flow

let serve_flow ~clock:_ ~config ~stopping ~stop ~busy flow handler =
  let r =
    {
      flow :> Eio.Flow.two_way_ty Eio.Resource.t;
      scratch = Cstruct.create 8192;
      pos = 0;
      len = 0;
    }
  in
  let rec loop ordinal =
    if !stopping then ()
    else
      let parsed =
        try
          Some
            (match stop with
            | None -> parse_head r config
            | Some stop ->
                Eio.Fiber.first
                  (fun () -> parse_head r config)
                  (fun () ->
                    Eio.Promise.await stop;
                    raise End_of_file))
        with End_of_file -> None
      in
      match parsed with
      | None -> ()
      | Some (method_, target, version, headers, length, chunked) ->
          busy := true;
          let path, query = Request.split_target target in
          let body = request_body r config method_ target length chunked in
          let request : Request.t =
            {
              id = lazy (string_of_int ordinal);
              version;
              scheme = "http";
              authority = header "host" headers;
              method_;
              target;
              path;
              query;
              headers;
              body;
              trailers = (fun () -> Ok Header.empty);
              peer = { address = None; port = None };
              tls = false;
              alpn_protocol = None;
              stream_id = None;
              connection_id = "h1";
            }
          in
          let response =
            match handler request with
            | Ok r -> r
            | Error error -> Handler.default_error_response error
          in
          let consumed = body.Body.done_ in
          let keep =
            (not !stopping) && consumed
            && (match version with Version.H1_1 -> true | _ -> false)
            &&
            match header "connection" headers with
            | Some value -> not (has_token "close" value)
            | None -> true
          in
          write_response flow config ~close:(not keep) ~head:(String.equal method_ "HEAD")
            response;
          busy := false;
          if keep then loop (ordinal + 1)
  in
  try loop 1 with
  | Invalid_request (status, message) -> (
      try
        write_response flow config ~close:true ~head:false
          (Response.text ~status (message ^ "\n"))
      with _ -> ())
  | End_of_file -> ()

let run_h1_on_socket ~sw:_ ~clock ?stop ?(drain_timeout = Ox.Duration.seconds 30)
    ?(config = Config.default) ?(on_error = fun _ -> ()) ~socket handler =
  if
    config.max_request_line_bytes <= 0
    || config.max_request_header_bytes <= 0
    || config.max_request_headers <= 0
    || config.max_request_body_bytes < 0
    || config.max_response_header_bytes <= 0
  then invalid_arg "Server: invalid config";
  let stopping = ref false in
  let flows = ref [] in
  let active = ref 0 in
  let remove flow = flows := List.filter (fun (x, _) -> x != flow) !flows in
  let close_idle () =
    List.iter
      (fun (flow, busy) -> if not !busy then try Eio.Flow.close flow with _ -> ())
      !flows
  in
  let run inner_sw =
    let rec accept () =
      let flow, _ = Eio.Net.accept ~sw:inner_sw socket in
      let busy = ref false in
      flows := (flow, busy) :: !flows;
      active := !active + 1;
      Eio.Fiber.fork ~sw:inner_sw (fun () ->
          Fun.protect
            ~finally:(fun () ->
              active := !active - 1;
              remove flow;
              Eio.Cancel.protect (fun () -> Eio.Flow.close flow))
            (fun () ->
              try serve_flow ~clock ~config ~stopping ~stop ~busy flow handler with
              | Eio.Cancel.Cancelled _ as e -> raise e
              | e -> on_error e));
      accept ()
    in
    match stop with
    | None -> accept ()
    | Some stop -> (
        Eio.Fiber.first (fun () -> Eio.Promise.await stop) accept;
        stopping := true;
        close_idle ();
        try
          Eio.Time.with_timeout_exn clock (Ox.Duration.to_seconds_float drain_timeout)
            (fun () ->
              while !active > 0 do
                Eio.Fiber.yield ()
              done)
        with Eio.Time.Timeout -> Eio.Switch.fail inner_sw Eio.Time.Timeout)
  in
  try Eio.Switch.run run with Eio.Time.Timeout -> ()

let run_h1 ~sw ~net ~clock ?stop ?drain_timeout ?config ?on_error ~addr handler =
  let socket = Eio.Net.listen net ~sw ~backlog:128 ~reuse_addr:true addr in
  run_h1_on_socket ~sw ~clock ?stop ?drain_timeout ?config ?on_error ~socket handler
