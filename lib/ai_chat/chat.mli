(** The OpenAI-compatible chat client: one non-streaming completion.

    [Chat.complete] writes one request — the model, the messages, and the caller's cap,
    JSON-object requirement and reasoning control — posts it through {!Ox_ai.Transport} to
    an OpenAI-compatible `chat/completions` endpoint (OpenRouter by default), and reads
    the first choice's content and usage out of the reply, fail-closed and bounded on both
    sides (^nchat-dys0 ^nchat-wtog).

    Cancellation and finalizers: {!complete} runs in the calling fiber, opens and closes
    one socket per attempt through {!Ox_http.Client}, sleeps its backoff on the caller's
    clock and registers no finalizer. Cancelling the fiber closes the socket of the
    attempt in flight; the typed result is [`Timeout] when the caller's deadline passed,
    and cancellation itself propagates as [Eio.Cancel.Cancelled] and is classified by
    [Ox.Scope.run] at the boundary. *)

val default_endpoint : string
(** [https://openrouter.ai/api/v1/chat/completions]: the OpenRouter route, the reference
    text helper's endpoint. *)

type t
(** A configured client: the transport, the clock, the logger, the endpoint, the key and
    the bounds. *)

val create :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  ?endpoint:string ->
  api_key:Ox_observability.Redact.t ->
  ?timeout:Ox.Duration.t ->
  ?max_request_bytes:int ->
  unit ->
  t
(** [create ~http ~clock ~logger ?endpoint ~api_key ?timeout ?max_request_bytes ()] is a
    client. [endpoint] defaults to {!default_endpoint} and is the full URL of the
    `chat/completions` route, so an OpenAI-compatible server of any base URL works — a
    DeepSeek key, a local model server, or a fake server in a test. [api_key] is a
    {!Ox_observability.Redact.t}: only {!Ox_ai.Bearer.header} reveals it, on the request
    path. [timeout] (10 s by default) caps one attempt's read and [max_request_bytes] (4
    MiB by default) bounds the serialized request. Pure and synchronous: it takes no
    switch, opens no socket and registers no finalizer. *)

val complete :
  t ->
  deadline:Ox.Duration.t ->
  model:string ->
  messages:Types.message list ->
  ?max_tokens:int ->
  ?json_object:bool ->
  ?reasoning:[ `Disabled | `Effort of string ] ->
  unit ->
  (Codecs.completion, Ox_ai.Error.t) result
(** [complete client ~deadline ~model ~messages ?max_tokens ?json_object ?reasoning ()]
    POSTs one chat completion and returns its first choice with the usage the reply
    reported.

    [messages] are the system and user messages in order. [json_object] (default [false])
    sends [response_format: {"type": "json_object"}], so the reply's content is required
    to be JSON by the endpoint (^nchat-02vr). [reasoning] sends OpenRouter's
    [{"enabled": false}] for [`Disabled] and [{"effort": e}] for [`Effort e], and omits
    the member entirely when the caller says nothing (^nchat-6kd8). [max_tokens] is sent
    when given and omitted when not.

    The states of failure, all inside [deadline], all under the two-attempt policy of
    {!Ox_ai.Transport}:
    - [`Input_too_large bound] — the serialized request is over the bound (4 MiB by
      default); nothing was sent.
    - [`Invalid_response issue] — the reply is not the documented shape (text that is not
      JSON, a required member missing or wrongly typed, or a first choice whose `content`
      is not a string), its body exceeded 1 MiB, or its status is one no answer can come
      from.
    - [`Authentication why] — HTTP 401.
    - [`Unavailable failure] — no reply came, or the endpoint answered with a status that
      is not an answer; [failure.retryable] says whether another attempt is reasonable.
    - [`Timeout] — the deadline passed, or an attempt's own read timed out.

    [`Model_mismatch] is never returned: the model is per call and a provider may route a
    request, so the model the reply named travels in {!Codecs.completion.model} for a
    caller that pins one.

    A successful call logs `model`, `prompt_tokens`, `completion_tokens`, `total_tokens`
    and `request_id` at debug under the message ["chat"], and the provider's own `cost`
    when the reply reports one (^nchat-96zw ^nchat-qu3j). A reply that reports no cost
    logs no `cost` field: nothing is not zero. *)
