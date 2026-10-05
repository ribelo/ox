(** One OpenAI-compatible chat completion, with text and image-URL request parts.

    [Ox_ai_chat.complete] is {!Chat.complete} under the name Leash's drive spec uses
    (drive-ls3c) and [Ox_ai_chat.Chat.complete] is the same call under the name {!Chat}
    documents; [t] is manifestly {!Chat.t}, so the two spellings interchange freely.

    Cancellation and finalizers: nothing in this package owns a resource. {!Chat.complete}
    performs HTTP in the calling fiber and closes each attempt's socket; see its contract.
*)

module Types = Types
(** The chat wire types. *)

module Codecs = Codecs
(** The completion a caller gets and the step that extracts it from a reply. *)

module Chat = Chat
(** The configured client and [complete]. *)

type t = Chat.t
(** A configured client; the same type as {!Chat.t}. *)

val default_endpoint : string
(** [https://openrouter.ai/api/v1/chat/completions]; the same constant as
    {!Chat.default_endpoint}. *)

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
(** [create] is {!Chat.create}.

    Suspension: never suspends; this call only constructs or reads OCaml values and
    captures dependencies without invoking them. Cancellation: not a cancellation point;
    this call performs no Eio cancellation check. Finalizers: this call registers no
    switch hook and leaves captured resources with their existing owner. Locking: this
    call acquires no lock; construction of synchronization objects does not acquire them.
    ^nlintd-a7oq *)

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
(** [complete] is {!Chat.complete}: one non-streaming chat completion with the caller's
    response format and reasoning control, decoded fail-closed. Messages carry ordered
    text/image-URL parts; replies retain required string content. Use
    {!Types.text_message} or {!Types.image_png}, and configure {!create} for a larger
    image request bound.

    Suspension: may suspend in Ox_ai.Transport.post_json for HTTP, deadlines and backoff,
    and in Ox_observability.Logger.debug through the caller's sink. Cancellation:
    propagates Eio.Cancel.Cancelled from transport or logger suspension; deadline expiry
    returns [Error `Timeout]. Finalizers: this call registers none; Ox_http.Client.request
    owns and closes each attempt's socket on return, failure or cancellation. Locking: no
    lock is acquired here; transport and logger synchronization is delegated to those
    dependencies. Cancellation safety: unsafe because progress is lost; a transmitted
    request may already have remote effects and restarting can repeat them. ^nimg-c8v5 *)
