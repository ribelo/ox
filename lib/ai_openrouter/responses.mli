(** Cancellation and finalizers: Suspension: may suspend in the delegated Ox_ai.Transport
    HTTP request and response I/O. Cancellation: propagates Eio.Cancel.Cancelled from that
    request. Finalizers: per-request socket cleanup belongs to the transport; this wrapper
    registers no hook. Locking: delegated to the transport. Cancellation safety: unsafe
    because progress is lost if the response is interrupted; remote processing is not
    rolled back. ^nlintd-z5p5 ^nlintd-vneh *)

type schema = { name : string; schema : Ox_json.t; strict : bool option }
(** Pie Responses with audio or text input. Each call is bounded by its supplied total
    deadline; cancellation closes the HTTP socket, with no additional finalizer. *)

type format = Text | Json_object | Json_schema of schema

type request = {
  model : string;
  prompt : string;
  wav : bytes;
  temperature : float option;
  text_format : format option;
  reasoning_effort : string option;
}

type audio_format =
  | Wav
  | Mp3
      (** Supported Responses audio formats. OGG is not accepted by this endpoint. The
          bytes retain the [request.wav] field name for source compatibility
          (^oxpie-a4m7). *)

type text_request = {
  model : string;
  instructions : string;
  input : string;
  temperature : float option;
  text_format : format option;
  reasoning_effort : string option;
}

type function_call = { name : string option; call_id : string option }
(** The identity of a tool continuation: the tool the model asked to call and the
    provider's call id, each [None] when the provider named none. The call's arguments are
    deliberately not decoded: a caller that must refuse a tool continuation does not need
    them, and they are model-authored data a sanitized diagnostic must not carry
    (^nor-pn0b). *)

type output =
  | Output_text of string
      (** A message's [output_text] content part, or an [output_text] item: the text this
          endpoint exists to deliver. *)
  | Function_call of function_call
      (** A [function_call] item: the reply asks for a tool continuation, not an answer.
      *)
  | Refusal of string
      (** A [refusal] content part or item: the model declined and this is what it said
          instead of answering. *)
  | Other of string
      (** An item, or a content part, of any other kind; the string is the [type] the
          provider named. Reported rather than dropped, so the caller decides what it can
          deliver (^nor-pn0b). *)

type response = {
  id : string option;
  model : string option;
  status : string;  (** The provider's status, as it arrived. *)
  text : string;
      (** The concatenation of the non-empty {!Output_text} items, in order. This is a
          projection of [output], not a delivery verdict: a reply that also carries a
          function call or a refusal has its text here too. Read {!deliverable} before
          delivering anything. *)
  output : output list;
      (** Every item of the reply's [output] array, in the provider's order, each tagged
          with its kind. Nothing is dropped. *)
}

type rejection =
  [ `Not_completed of string
    (** [status] is not ["completed"]; the string is the value that arrived. *)
  | `Tool_continuation of function_call
    (** The reply asks for a tool. This endpoint returns text, so it cannot answer. *)
  | `Refusal of string  (** The model declined; the string is its refusal. *)
  | `Other of string
    (** An output item kind this endpoint cannot deliver; the string is its [type]. *) ]

val default_endpoint : string

val encode : ?audio_format:audio_format -> ?instructions:string -> request -> Ox_json.t
(** [audio_format] defaults to [Wav]. [instructions], when supplied, is separate from the
    user message's [prompt] text. Pure; performs no I/O. *)

val encode_text : text_request -> Ox_json.t
(** Rendered [instructions] plus exactly one user message containing [input], with no
    audio part. Pure; performs no I/O (^oxpie-d3t9). *)

val decode : Ox_json.t -> (response, Ox_ai.Error.t) result
(** [decode json] is the reply's status, identity, concatenated text and every output
    item, in order.

    A reply whose [status] is ["failed"] is [`Invalid_response], as before. Every other
    status is reported as it arrived, so the caller decides what it can deliver. Content
    this module reads but cannot parse — a text part without text, a refusal without a
    refusal string, an [output] that is not an array — is [`Invalid_response], never
    silently empty text. Pure and synchronous: it performs no I/O and registers no
    finalizer. *)

val deliverable : response -> (string, rejection) result
(** [deliverable response] is [Ok text] only when [status] is ["completed"] and every
    output item is {!Output_text} or [Other "reasoning"]: the verdict a text consumer must
    obey, so that a completed reply carrying a function call is never delivered as text
    (^nor-pn0b). Reasoning items remain in [response.output] for inspection but contribute
    no delivered text and do not disqualify the reply (^oxpie-c8r5).

    [Error rejection] names the first disqualifying finding in the provider's item order,
    after the status: [`Not_completed status], [`Tool_continuation call], [`Refusal text]
    or [`Other kind]. A completed reply with no output items at all is [Ok ""]: the
    absence of disqualifiers is not a claim that the reply said anything. Pure and
    synchronous: it performs no I/O and registers no finalizer. *)

val create :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  api_key:Ox_observability.Redact.t ->
  ?endpoint:string ->
  ?audio_format:audio_format ->
  ?instructions:string ->
  ?timeout:Ox.Duration.t ->
  ?max_request_bytes:int ->
  ?max_response_bytes:int ->
  ?response_idle:Ox.Duration.t ->
  deadline:Ox.Duration.t ->
  request ->
  (response, Ox_ai.Error.t) result
(** One non-streaming audio call to [endpoint]. [max_request_bytes] bounds the complete
    encoded JSON, including base64 and framing, before any I/O (default 4 MiB); provider
    413 reports the effective bound (^oxpie-b6q2). [max_response_bytes] bounds the reply
    (default 1 MiB). [timeout] caps each attempt (ten seconds by default); [response_idle]
    resets on each incoming response read and bounds silence (^oxpie-e5v1). Both remain
    separate from the total [deadline], which includes retries and backoff: the earliest
    budget wins, returning [`Timeout]. Raise [timeout] with a longer idle policy to permit
    long progressing replies. Defaults and retries otherwise stay those of
    {!Ox_ai.Transport.post_json}. Cancellation closes the socket and no finalizer is
    registered. *)

val create_text :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  api_key:Ox_observability.Redact.t ->
  ?endpoint:string ->
  ?timeout:Ox.Duration.t ->
  ?max_request_bytes:int ->
  ?max_response_bytes:int ->
  ?response_idle:Ox.Duration.t ->
  deadline:Ox.Duration.t ->
  text_request ->
  (response, Ox_ai.Error.t) result
(** One non-streaming text-only call with the same transport bounds, decoder and
    {!deliverable} verdict as {!create}. Model, instructions and input must be nonempty;
    non-finite temperature is [`Invalid_response] before I/O. Cancellation closes the
    socket and no finalizer is registered (^oxpie-d3t9). *)
