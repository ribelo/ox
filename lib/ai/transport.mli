(** Bounded JSON POST with the AI retry policy and typed failures.

    One call is one decision: {!post_json} serializes nothing itself — the caller hands
    the exact bytes — refuses a request past the caller's byte bound before any socket
    exists, sends once by default, and returns the peer's raw status and body.

    A timeout, transport failure or lost reply does not prove the POST had no remote
    effect. The default {!Never_replay} policy refuses automatic repetition, including
    after HTTP 429/529: no operation contract here proves those statuses precede commit.
    {!Allow_duplicate_effects} explicitly accepts possible duplicate remote effects, not
    idempotency. Only with that consent does the bounded reference retry schedule apply:
    transport failures, attempt timeouts and 429/529, with 100 ms backoff. The whole call,
    backoff included, is bounded by the caller's {!Ox.Duration.t} deadline. ^safe-o2b6
    ^safe-a5mq ^safe-3o27 ^safe-s51t

    Cancellation and finalizers: {!post_json} runs in the calling fiber, sleeps on the
    caller's clock, and owns no switch; each attempt's socket is opened and closed by
    {!Ox_http.Client.request}, so cancellation closes the socket and a cancelled call
    leaves no local socket behind. No finalizer is registered here; a request already
    transmitted can still have remote effects.

    Suspension: may suspend in Client.request, Eio.Time.sleep backoff and the timeout
    wrapper; delegates HTTP to Ox_http.Client.request, time reads to Eio.Time.now,
    deadline arithmetic to Ox.Duration and Ox.Timeout, diagnostics to
    Ox_observability.Logger.debug, and parsing/byte/string operations to Stdlib.
    Cancellation: propagates Eio.Cancel.Cancelled from external cancellation; deadline
    expiry returns [Error `Timeout]; delegates HTTP/deadline checks to
    Ox_http.Client.request and Ox.Timeout, clock access to Eio.Time, diagnostics to
    Ox_observability.Logger.debug, and numeric/parsing operations to Ox.Duration and
    Stdlib. Finalizers: Client.request owns and closes each attempt's socket on return,
    failure or cancellation. Locking: this wrapper holds no lock; logger sinks and
    Client.request delegate their own synchronization. Cancellation safety: unsafe because
    progress is lost; cancellation does not undo a transmitted POST and restarting may
    repeat server-side effects. ^nlintd-a7oq ^nlintd-4ja0

    ^nso-y4rw ^nso-77t7 ^nso-zmfp *)

type response = { status : int; body : bytes }
(** What the endpoint answered: the HTTP status and the raw body. Decoding is the
    client's, because each AI endpoint documents its own reply. *)

(** Operation-specific permission to repeat a JSON POST. [Never_replay] is the default.
    [Allow_duplicate_effects] is explicit consent to possible duplicate remote effects; it
    supplies no proof of idempotency, provider deduplication or non-commit. A caller must
    decide whether its domain tolerates duplicates before choosing it. ^safe-o2b6
    ^safe-a5mq *)
type replay_policy = Never_replay | Allow_duplicate_effects

val default_timeout : Ox.Duration.t
(** [Ox.Duration.seconds 10]: the ceiling on one attempt's read, the reference adapter's
    transport timeout. *)

val default_max_request_bytes : int
(** [4 * 1024 * 1024]: the serialized request bound. *)

val default_max_response_bytes : int
(** [1024 * 1024]: the response bound, enforced while reading by {!Ox_http.Client}. *)

val max_attempts : int
(** [2]: the default attempt ceiling, not replay permission. {!Never_replay} still sends
    at most once. ^safe-s51t *)

val backoff : Ox.Duration.t
(** [Ox.Duration.ms 100]: the fixed delay between permitted attempts. *)

val post_json :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  ?timeout:Ox.Duration.t ->
  ?response_idle:Ox.Duration.t ->
  ?max_request_bytes:int ->
  ?max_response_bytes:int ->
  ?max_attempts:int ->
  ?replay_policy:replay_policy ->
  endpoint:string ->
  authorization:(string * string) list ->
  body:bytes ->
  deadline:Ox.Duration.t ->
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
    429 and 529 are [`Unavailable] with [retryable = true], any other 5xx is
    [`Unavailable] with [retryable = false], and a status no answer can come from — the
    3xx the reference refuses to follow — is [`Unavailable] as well.

    [`Timeout] is the caller's deadline passing or one attempt's read timing out;
    [`Unavailable] with [retryable = true] is a connect, TLS or protocol failure, or a
    connection that closed mid-reply. Those two, and a 429/529, permit another attempt
    only under [replay_policy = Allow_duplicate_effects] and within [max_attempts].
    [retryable = true] is an error classification, not evidence that repetition is safe. A
    body over the response bound is [`Invalid_response] and stops after one attempt.

    [response_idle], when supplied, resets on each incoming response read within each
    attempt. It is independent of [timeout] and [deadline]; an idle expiry is [`Timeout]
    and follows the same explicit replay policy (^oxpie-e5v1 ^safe-3o27).

    A negative [max_request_bytes] refuses every request.

    [max_response_bytes] (default {!default_max_response_bytes}) bounds the reply read;
    [max_attempts] (default {!max_attempts}, at least 1) bounds permitted attempts but
    never authorizes replay. With [Never_replay] or [max_attempts = 1], the call makes at
    most one request and never backs off. No general Ox retry scheduling is changed.
    Either out of range raises [Invalid_argument]. A non-2xx reply's [Retry-After]
    (delta-seconds or IMF-fixdate) is carried as [retry_after] in [`Unavailable].
    ^nai-97as ^nai-337c ^nai-rjkq ^nlintd-raises

    @raise Invalid_argument if [max_response_bytes <= 0] or [max_attempts < 1]. *)

val bytes_of_json : Yojson.Safe.t -> bytes
(** [bytes_of_json json] is the compact UTF-8 encoding of [json] as the request body
    {!post_json} sends. Pure; it neither suspends nor registers a finalizer. *)

val retryable_status : int -> bool
(** [retryable_status status] is [true] for 429 and 529: the two statuses the reference
    adapter considers for retry. A client maps them to [`Unavailable]; this predicate
    neither proves non-commit nor authorizes replay. ^safe-a5mq *)
