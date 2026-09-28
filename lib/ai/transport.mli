(** Bounded JSON POST with the AI retry policy and typed failures.

    One call is one decision: {!post_json} serializes nothing itself — the caller hands
    the exact bytes — refuses a request past the caller's byte bound before any socket
    exists, sends at most two attempts, and returns the peer's raw status and body.

    The policy is copied from the reference adapter ([reference/jev.ts]): two attempts,
    the second only after a transport failure, an attempt's own timeout, or HTTP 429 or
    529, with a 100 ms backoff on the caller's clock; every other failure stops at the
    first attempt. The whole call, backoff included, is bounded by the caller's
    {!Eta.Duration.t} deadline.

    Cancellation and finalizers: {!post_json} runs in the calling fiber, sleeps on the
    caller's clock, and owns no switch; each attempt's socket is opened and closed by
    {!Eta_http.Client.request}, so cancellation closes the socket and a cancelled call
    leaves nothing behind. No finalizer is registered here.

    ^nso-y4rw ^nso-77t7 ^nso-zmfp *)

type response = { status : int; body : bytes }
(** What the endpoint answered: the HTTP status and the raw body. Decoding is the
    client's, because each AI endpoint documents its own reply. *)

val default_timeout : Eta.Duration.t
(** [Eta.Duration.seconds 10]: the ceiling on one attempt's read, the reference adapter's
    transport timeout. *)

val default_max_request_bytes : int
(** [4 * 1024 * 1024]: the serialized request bound. *)

val default_max_response_bytes : int
(** [1024 * 1024]: the response bound, enforced while reading by {!Eta_http.Client}. *)

val max_attempts : int
(** [2]: the number of attempts one {!post_json} call may make. *)

val backoff : Eta.Duration.t
(** [Eta.Duration.ms 100]: the fixed delay between the two attempts. *)

val post_json :
  http:Eta_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Eta_observability.Logger.t ->
  ?timeout:Eta.Duration.t ->
  ?max_request_bytes:int ->
  ?max_response_bytes:int ->
  ?max_attempts:int ->
  endpoint:string ->
  authorization:(string * string) list ->
  body:bytes ->
  deadline:Eta.Duration.t ->
  unit ->
  (response, Error.t) result
(** [post_json ~http ~clock ~logger ~endpoint ~authorization ~body ~deadline ()] POSTs
    [body] to [endpoint] with the [authorization] header and
    [Content-Type: application/json].

    The request is refused as [`Input_too_large] when it is longer than
    [max_request_bytes] (4 MiB by default) — nothing is sent. The response is read under
    {!default_max_response_bytes} (1 MiB) and a larger one is [`Invalid_response].

    A 2xx status returns the body for the caller to decode. Every other status becomes a
    typed failure here, because the mapping is the contract's and not a client's: 401 is
    [`Authentication], 413 is [`Input_too_large], any other 4xx is [`Invalid_response],
    429 and 529 are retried first and then [`Unavailable] with [retryable = true], any
    other 5xx is [`Unavailable] with [retryable = false], and a status no answer can come
    from — the 3xx the reference refuses to follow — is [`Unavailable] as well.

    [`Timeout] is the caller's deadline passing or one attempt's read timing out;
    [`Unavailable] with [retryable = true] is a connect, TLS or protocol failure, or a
    connection that closed mid-reply. Those two, and a 429/529, consume the second
    attempt; a body over the response bound is [`Invalid_response] and does not, exactly
    as the reference's bound read ends its call after one attempt.

    A negative [max_request_bytes] refuses every request.

    [max_response_bytes] (default {!default_max_response_bytes}) bounds the reply read;
    [max_attempts] (default {!max_attempts}, at least 1) is how many attempts the call may
    make: [1] for a caller that owns its retry policy, one request and no backoff. Either
    out of range raises [Invalid_argument]. A non-2xx reply's [Retry-After] (delta-seconds
    or IMF-fixdate) is carried as [retry_after] in [`Unavailable]. ^nai-97as ^nai-337c
    ^nai-rjkq *)

val bytes_of_json : Yojson.Safe.t -> bytes
(** [bytes_of_json json] is the compact UTF-8 encoding of [json] as the request body
    {!post_json} sends. Pure; it neither suspends nor registers a finalizer. *)

val retryable_status : int -> bool
(** [retryable_status status] is [true] for 429 and 529: the two statuses the reference
    adapter retries. A client maps them to [`Unavailable]. *)
