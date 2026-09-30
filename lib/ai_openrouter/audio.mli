type request = {
  model : string;
  filename : string;
  wav : bytes;
  language : string option;
  prompt : string option;
  temperature : float option;
}
(** Bounded WAV multipart transcription for Pie. The HTTP request owns its socket and
    closes it on completion or cancellation; this module registers no finalizer. *)

val default_endpoint : string

val max_request_bytes : int
(** The default bound on one encoded multipart body: 8 MiB, unchanged by ^nor-474w. *)

val body : ?max_request_bytes:int -> request -> (bytes, Ox_ai.Error.t) result
(** [body ?max_request_bytes request] encodes the multipart body — the model and optional
    language, prompt and temperature parts, then the WAV file — and refuses it with
    [`Input_too_large { limit; length }] when the encoded body is longer than the bound.
    The bound defaults to {!max_request_bytes}, and [length] is the length of the whole
    encoded body, so the WAV and the multipart overhead are both covered (^nor-474w). Pure
    and synchronous: it performs no I/O and registers no finalizer.

    @raise Invalid_argument
      when the bound is not positive. A bound that admits nothing is a programming defect,
      not a provider failure. *)

val decode : Ox_json.t -> (string, Ox_ai.Error.t) result

val create :
  http:Ox_http.Client.t ->
  api_key:Ox_observability.Redact.t ->
  ?endpoint:string ->
  ?max_request_bytes:int ->
  ?response_idle:Ox.Duration.t ->
  deadline:Ox.Duration.t ->
  request ->
  (string, Ox_ai.Error.t) result
(** [create ... request] uploads the body built by {!body} to [endpoint] and decodes the
    transcription text.

    A body over the bound is [`Input_too_large] before any network I/O; a provider 413 is
    the same typed error carrying the effective bound. The call is bounded by [deadline];
    cancellation closes its HTTP socket and no finalizer is registered. [response_idle]
    optionally bounds each incoming response read, resetting with progress rather than
    limiting the total response duration; expiry is [`Timeout] (^oxpie-f7w4).

    @raise Invalid_argument when the supplied bound is not positive (see {!body}). *)
