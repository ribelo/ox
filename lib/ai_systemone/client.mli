(** The System One (JEV) client.

    One call answers choice and score questions over a JSON state, fail-closed: the
    request is bounded before it is sent, the reply is decoded field by field with no
    default, the reply's model must be the configured one, and a second attempt happens
    only after a transport failure, an attempt's own timeout, or HTTP 429/529 (^nso-5hom
    ^nso-megl ^nso-ttfj ^nso-pflg ^nso-zmfp).

    Two endpoints serve the same contract and both work: {!default_endpoint},
    [https://openrouter.ai/api/v1/systemone], and {!typesafe_endpoint},
    [https://api.typesafe.ai/v1/systemone] — whichever the key belongs to. The endpoint is
    `~endpoint` at {!create}, so a test points the client at a local server.

    Cancellation and finalizers: {!evaluate} runs in the calling fiber, opens and closes
    one socket per attempt through {!Ox_http.Client}, sleeps its backoff on the caller's
    clock and registers no finalizer. Cancelling the fiber closes the socket of the
    attempt in flight; the typed result is [`Timeout] when the caller's deadline passed,
    and cancellation itself propagates as [Eio.Cancel.Cancelled] and is classified by
    [Ox.Scope.run] at the boundary. *)

val default_endpoint : string
(** [https://openrouter.ai/api/v1/systemone]: the endpoint the reference client uses. *)

val typesafe_endpoint : string
(** [https://api.typesafe.ai/v1/systemone]: the endpoint jev-ultrafast posts to. The same
    contract, so either `~endpoint` works. *)

type t
(** A configured client: the transport, the clock, the endpoint, the key and the model. *)

val create :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  ?endpoint:string ->
  api_key:Ox_observability.Redact.t ->
  model:string ->
  ?timeout:Ox.Duration.t ->
  ?max_request_bytes:int ->
  unit ->
  t
(** [create ~http ~clock ~logger ?endpoint ~api_key ~model ()] is a client. [endpoint]
    defaults to {!default_endpoint}; [api_key] is a {!Ox_observability.Redact.t}, so the
    key cannot reach a log line by accident, and only {!Ox_ai.Bearer.header} reveals it,
    on the request path. [timeout] (10 s by default) is the ceiling on one attempt's read
    and [max_request_bytes] (4 MiB by default) the bound on the serialized request. Pure
    and synchronous: it takes no switch, opens no socket and registers no finalizer.

    Suspension: never suspends; this call only constructs or reads OCaml values and
    captures dependencies without invoking them. Cancellation: not a cancellation point;
    this call performs no Eio cancellation check. Finalizers: this call registers no
    switch hook and leaves captured resources with their existing owner. Locking: this
    call acquires no lock; construction of synchronization objects does not acquire them.
    ^nlintd-a7oq *)

val evaluate :
  t ->
  deadline:Ox.Duration.t ->
  state:Yojson.Safe.t ->
  questions:(string * Codecs.question) list ->
  (Codecs.response, Ox_ai.Error.t) result
(** [evaluate client ~deadline ~state ~questions] POSTs [{"model"; "state"; "questions"}]
    and returns the decoded reply.

    The states of failure, all inside [deadline], all under the two-attempt policy of
    {!Ox_ai.Transport}:
    - [`Input_too_large bound] — the serialized request is over the bound (4 MiB); nothing
      was sent.
    - [`Invalid_response issue] — the reply is not the documented shape (a missing field,
      a wrong type, an unknown answer discriminant, invalid JSON), its body exceeded 1
      MiB, or its status is one no answer can come from.
    - [`Authentication why] — HTTP 401.
    - [`Model_mismatch { expected; got }] — the reply names another model.
    - [`Unavailable failure] — no reply came, or the endpoint answered with a status that
      is not an answer; [failure.retryable] says whether another attempt is reasonable.
      [`Timeout] — the deadline passed, or an attempt's own read timed out.

    A reply that a provider rejects for context length (the reference adapter's 400/422
    heuristic) is read as [`Invalid_response], not [`Input_too_large]: this client bounds
    what it sends and does not guess what the endpoint meant.

    A successful call logs `model`, `input_tokens`, `output_tokens`, `cost` and
    `request_id` at debug under the message ["systemone"] (^nso-61ka). *)

val answer : string -> Codecs.response -> Codecs.answer option
(** [answer name response] is the answer named [name] when the reply names one, and [None]
    otherwise — absent rather than defaulted, so a caller decides what a missing answer
    means. Pure. *)
