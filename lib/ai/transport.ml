type response = { status : int; body : bytes }
type replay_policy = Never_replay | Allow_duplicate_effects

let default_timeout = Ox.Duration.seconds 10
let default_max_request_bytes = 4 * 1024 * 1024
let default_max_response_bytes = 1024 * 1024
let max_attempts = 2
let backoff = Ox.Duration.ms 100
let retryable_status status = status = 429 || status = 529

(* ^nai-rjkq: Retry-After is delta-seconds or an HTTP-date (RFC 9110 10.2.3). Only the
   IMF-fixdate form is read ("Sun, 06 Nov 1994 08:49:37 GMT"); the obsolete forms, any
   invalid value and a date already past are None. *)
let days_from_civil y m d =
  let y = if m <= 2 then y - 1 else y in
  let era = (if y >= 0 then y else y - 399) / 400 in
  let yoe = y - (era * 400) in
  let mp = (m + 9) mod 12 in
  let doy = (((153 * mp) + 2) / 5) + d - 1 in
  let doe = (yoe * 365) + (yoe / 4) - (yoe / 100) + doy in
  (era * 146097) + doe - 719468

let months =
  [ "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" ]

let http_date value =
  try
    Scanf.sscanf value "%3s, %2d %3s %4d %2d:%2d:%2d GMT%!" (fun _ d mon y hh mm ss ->
        let rec find i = function
          | [] -> None
          | x :: rest -> if x = mon then Some i else find (i + 1) rest
        in
        match find 1 months with
        | Some m when d >= 1 && d <= 31 && hh < 24 && mm < 60 && ss < 61 ->
            Some
              (float_of_int
                 ((days_from_civil y m d * 86400) + (hh * 3600) + (mm * 60) + ss))
        | _ -> None)
  with Scanf.Scan_failure _ | End_of_file | Failure _ -> None

let retry_after ~now headers =
  match
    List.find_opt (fun (name, _) -> String.lowercase_ascii name = "retry-after") headers
  with
  | None -> None
  | Some (_, raw) -> (
      let value = String.trim raw in
      if value <> "" && String.for_all (fun c -> c >= '0' && c <= '9') value then
        Option.map Ox.Duration.seconds (int_of_string_opt value)
      else
        match http_date value with
        | Some at when at > now ->
            Some (Ox.Duration.ms (int_of_float (Float.ceil ((at -. now) *. 1000.))))
        | _ -> None)

(* The one boundary where ox_http's typed transport errors become this client's
   failures (^nso-77t7): a connection that never completed, a TLS failure, a framing
   error the peer caused and a connection that closed mid-reply are [`Unavailable]; an
   idle or overall read timeout is [`Timeout]; a body past the response bound is an
   [`Invalid_response] — the reference adapter's verdict, because the bytes that arrived
   are not the documented reply. *)
let transport_failure message =
  `Unavailable { Error.message; retryable = true; retry_after = None; status = None }

let map_error ~max_response_bytes : Ox_http.Client.error -> Error.t = function
  | `Timeout | `Idle_timeout | `Body { reason = `Timeout | `Idle_timeout; _ } -> `Timeout
  | `Body { reason = `Too_large; _ } ->
      `Invalid_response
        {
          Ox_json.path = "";
          message =
            Printf.sprintf "response body exceeds the %d-byte bound" max_response_bytes;
          got = `Null;
        }
  | `Closed -> transport_failure "the connection closed before the reply completed"
  | `Connect why -> transport_failure ("connect: " ^ why)
  | `Tls why -> transport_failure ("tls: " ^ why)
  | `Protocol why -> transport_failure ("protocol: " ^ why)
  | `Body { status; reason; _ } ->
      let message =
        match reason with
        | `Truncated -> "response body truncated"
        | `Malformed why -> "response body: " ^ why
        | `Tls why -> "tls: " ^ why
        | `Closed -> "connection closed during response body"
        | `Connect why -> "connect: " ^ why
        | `Timeout | `Idle_timeout | `Too_large -> assert false
      in
      `Unavailable
        { Error.message; retryable = true; retry_after = None; status = Some status }

(* Candidates under duplicate-effect consent only (^safe-o2b6 ^safe-a5mq): a
   transport failure, attempt timeout or HTTP 429/529. None proves the POST had no
   remote effect. This predicate classifies errors; the replay policy separately
   authorizes another attempt. The error's retryable flag is not permission. *)
let retryable_error (error : Error.t) =
  match error with
  | `Unavailable _ | `Timeout -> true
  | `Authentication _ | `Invalid_response _ | `Input_too_large _ | `Model_mismatch _ ->
      false

(* What a status means when no attempt is left. The mapping is the reference adapter's
   (`reference/jev.ts`): 401 is the key, 413 is a request the endpoint refused as too
   large, every other 4xx is a reply that is not the documented answer, and a 5xx is the
   provider failing. A status no client can answer from — the 3xx the reference refuses to
   follow — is [`Unavailable], like any other attempt that produced no reply. *)
let status_error ~max_request_bytes ~length ~retry_after status =
  if status = 401 then `Authentication (Printf.sprintf "HTTP %d" status)
  else if status = 413 then `Input_too_large { Ox_json.limit = max_request_bytes; length }
  else if status >= 400 && status < 500 then
    `Invalid_response
      {
        Ox_json.path = "";
        message = Printf.sprintf "HTTP %d is not an answer" status;
        got = `Null;
      }
  else
    `Unavailable
      {
        Error.message = Printf.sprintf "HTTP %d" status;
        retryable = false;
        retry_after;
        status = Some status;
      }

let attempt ~http ~url ~authorization ~body ~deadline ?response_idle ~max_response_bytes
    () =
  match
    Ox_http.Client.request http ~method_:"POST" ~url
      ~headers:(("Content-Type", "application/json") :: authorization)
      ~body ~deadline ?response_idle ~max_body_bytes:max_response_bytes ()
  with
  | Ok { status; headers; body = `Read body } -> Ok (status, headers, body)
  | Ok { body = `Skipped; _ } -> Error (transport_failure "unexpected skipped body")
  | Error error -> Error (map_error ~max_response_bytes error)

let bytes_of_json json = Bytes.of_string (Yojson.Safe.to_string json)

(* The backoff runs on the caller's clock, so the sleep is cancellable and testable: a
   mock clock advances it, and the caller's deadline — the [Ox.Timeout.timeout] wrapper
   {!post_json} installs — bounds it. *)
let wait ~clock ~logger duration =
  Ox_observability.Logger.debug logger
    ~fields:[ ("retry_in_ms", Ox_observability.Logger.Int (Ox.Duration.to_ms duration)) ]
    "retry";
  Eio.Time.sleep clock (Ox.Duration.to_seconds_float duration)

(* One attempt's verdict. It keeps the retry decision separate from the error's own kind:
   a 5xx reply is [`Unavailable] to the caller and is still not retried, because the
   reference retries only a transport failure, an attempt's timeout, and 429/529. *)
type verdict = Reply of response | Retry of Error.t | Final of Error.t

(* ^safe-s51t: at most [max_attempts] attempts, later ones only with explicit
   [Allow_duplicate_effects] consent and a retry candidate, all
   inside the caller's [deadline] because {!post_json} wraps this loop in one
   {!Ox.Timeout.timeout}. [timeout] caps one attempt's read so a hung peer cannot eat the
   whole budget. *)
let rec run ~http ~clock ~logger ~endpoint ~authorization ~body ~deadline ~timeout
    ?response_idle ~max_request_bytes ~max_response_bytes ~length ~replay_policy ~attempts
    () =
  let verdict =
    match
      attempt ~http ~url:endpoint ~authorization ~body ~max_response_bytes
        ~deadline:(Ox.Duration.min deadline timeout)
        ?response_idle ()
    with
    | Ok (status, _, body) when status >= 200 && status < 300 -> Reply { status; body }
    | Ok (status, headers, _) ->
        let retry_after = retry_after ~now:(Eio.Time.now clock) headers in
        if retryable_status status then
          Retry
            (`Unavailable
               {
                 Error.message = Printf.sprintf "HTTP %d" status;
                 retryable = true;
                 retry_after;
                 status = Some status;
               })
        else Final (status_error ~max_request_bytes ~length ~retry_after status)
    | Error error -> if retryable_error error then Retry error else Final error
  in
  match verdict with
  | Reply response -> Ok response
  | Final error -> Error error
  | Retry error ->
      if replay_policy = Never_replay || attempts <= 1 then Error error
      else (
        wait ~clock ~logger backoff;
        run ~http ~clock ~logger ~endpoint ~authorization ~body
          ~deadline:(Ox.Duration.subtract deadline backoff)
          ~timeout ?response_idle ~max_request_bytes ~max_response_bytes ~length
          ~replay_policy ~attempts:(attempts - 1) ())

let post_json ~http ~clock ~logger ?(timeout = default_timeout) ?response_idle
    ?(max_request_bytes = default_max_request_bytes)
    ?(max_response_bytes = default_max_response_bytes) ?(max_attempts = max_attempts)
    ?(replay_policy = Never_replay) ~endpoint ~authorization ~body ~deadline () =
  if max_response_bytes <= 0 then
    invalid_arg "Ox_ai.Transport.post_json: max_response_bytes must be positive";
  if max_attempts < 1 then
    invalid_arg "Ox_ai.Transport.post_json: max_attempts must be at least 1";
  let length = Bytes.length body in
  if length > max_request_bytes then
    Error (`Input_too_large { Ox_json.limit = max_request_bytes; length })
  else
    Ox.Timeout.timeout ~clock deadline (fun () ->
        run ~http ~clock ~logger ~endpoint ~authorization ~body ~deadline ~timeout
          ?response_idle ~max_request_bytes ~max_response_bytes ~length ~replay_policy
          ~attempts:max_attempts ())
