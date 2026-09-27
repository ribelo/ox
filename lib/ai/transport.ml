type response = { status : int; body : bytes }

let default_timeout = Eta.Duration.seconds 10
let default_max_request_bytes = 4 * 1024 * 1024
let default_max_response_bytes = 1024 * 1024
let max_attempts = 2
let backoff = Eta.Duration.ms 100
let retryable_status status = status = 429 || status = 529

(* The one boundary where eta_http's typed transport errors become this client's
   failures (^nso-77t7): a connection that never completed, a TLS failure, a framing
   error the peer caused and a connection that closed mid-reply are [`Unavailable]; an
   idle or overall read timeout is [`Timeout]; a body past the response bound is an
   [`Invalid_response] — the reference adapter's verdict, because the bytes that arrived
   are not the documented reply. *)
let transport_failure message = `Unavailable { Error.message; retryable = true }

let map_error : Eta_http.Client.error -> Error.t = function
  | `Timeout | `Idle_timeout -> `Timeout
  | `Body_too_large ->
      `Invalid_response
        {
          Eta_json.path = "";
          message = "response body exceeds the 1 MiB bound";
          got = `Null;
        }
  | `Closed -> transport_failure "the connection closed before the reply completed"
  | `Connect why -> transport_failure ("connect: " ^ why)
  | `Tls why -> transport_failure ("tls: " ^ why)
  | `Protocol why -> transport_failure ("protocol: " ^ why)

(* The attempt policy (^nso-zmfp): one more attempt, only after a transport failure, a
   timeout of the attempt itself, or HTTP 429/529 — nothing else. The reference adapter
   retries exactly those three in its loop (`reference/jev.ts`), and a body over its
   bound is none of them: it throws INVALID_RESPONSE, which is not retryable and ends the
   call after one attempt. This predicate is the attempt policy, not the caller's verdict:
   {!Error.retryable} answers that question. *)
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
let status_error ~max_request_bytes ~length status =
  if status = 401 then `Authentication (Printf.sprintf "HTTP %d" status)
  else if status = 413 then
    `Input_too_large { Eta_json.limit = max_request_bytes; length }
  else if status >= 400 && status < 500 then
    `Invalid_response
      {
        Eta_json.path = "";
        message = Printf.sprintf "HTTP %d is not an answer" status;
        got = `Null;
      }
  else `Unavailable { Error.message = Printf.sprintf "HTTP %d" status; retryable = false }

let attempt ~http ~url ~authorization ~body ~deadline =
  match
    Eta_http.Client.request http ~method_:"POST" ~url
      ~headers:(("Content-Type", "application/json") :: authorization)
      ~body ~deadline ~max_body_bytes:default_max_response_bytes ()
  with
  | Ok response -> Ok { status = response.Eta_http.Client.status; body = response.body }
  | Error error -> Error (map_error error)

let bytes_of_json json = Bytes.of_string (Yojson.Safe.to_string json)

(* The backoff runs on the caller's clock, so the sleep is cancellable and testable: a
   mock clock advances it, and the caller's deadline — the [Eta.Timeout.timeout] wrapper
   {!post_json} installs — bounds it. *)
let wait ~clock ~logger duration =
  Eta_observability.Logger.debug logger
    ~fields:
      [ ("retry_in_ms", Eta_observability.Logger.Int (Eta.Duration.to_ms duration)) ]
    "retry";
  Eio.Time.sleep clock (Eta.Duration.to_seconds_float duration)

(* One attempt's verdict. It keeps the retry decision separate from the error's own kind:
   a 5xx reply is [`Unavailable] to the caller and is still not retried, because the
   reference retries only a transport failure, an attempt's timeout, and 429/529. *)
type verdict = Reply of response | Retry of Error.t | Final of Error.t

(* At most [max_attempts] attempts, the later ones only under {!retryable_error}, all
   inside the caller's [deadline] because {!post_json} wraps this loop in one
   {!Eta.Timeout.timeout}. [timeout] caps one attempt's read so a hung peer cannot eat the
   whole budget. *)
let rec run ~http ~clock ~logger ~endpoint ~authorization ~body ~deadline ~timeout
    ~max_request_bytes ~length ~attempts =
  let verdict =
    match
      attempt ~http ~url:endpoint ~authorization ~body
        ~deadline:(Eta.Duration.min deadline timeout)
    with
    | Ok response when response.status >= 200 && response.status < 300 -> Reply response
    | Ok response when retryable_status response.status ->
        Retry
          (`Unavailable
             {
               Error.message = Printf.sprintf "HTTP %d" response.status;
               retryable = true;
             })
    | Ok response -> Final (status_error ~max_request_bytes ~length response.status)
    | Error error -> if retryable_error error then Retry error else Final error
  in
  match verdict with
  | Reply response -> Ok response
  | Final error -> Error error
  | Retry error ->
      if attempts <= 1 then Error error
      else (
        wait ~clock ~logger backoff;
        run ~http ~clock ~logger ~endpoint ~authorization ~body
          ~deadline:(Eta.Duration.subtract deadline backoff)
          ~timeout ~max_request_bytes ~length ~attempts:(attempts - 1))

let post_json ~http ~clock ~logger ?(timeout = default_timeout)
    ?(max_request_bytes = default_max_request_bytes) ~endpoint ~authorization ~body
    ~deadline () =
  let length = Bytes.length body in
  if length > max_request_bytes then
    Error (`Input_too_large { Eta_json.limit = max_request_bytes; length })
  else
    Eta.Timeout.timeout ~clock deadline (fun () ->
        run ~http ~clock ~logger ~endpoint ~authorization ~body ~deadline ~timeout
          ~max_request_bytes ~length ~attempts:max_attempts)
