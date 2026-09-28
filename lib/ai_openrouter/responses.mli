type schema = { name : string; schema : Eta_json.t; strict : bool option }
(** Pie Responses text plus input_audio/WAV. The call is bounded by the supplied deadline;
    cancellation closes the HTTP socket, with no additional finalizer. *)

type format = Text | Json_object | Json_schema of schema

type request = {
  model : string;
  prompt : string;
  wav : bytes;
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
val encode : request -> Eta_json.t

val decode : Eta_json.t -> (response, Eta_ai.Error.t) result
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
    output item is {!Output_text}: the verdict a text consumer must obey, so that a
    completed reply carrying a function call is never delivered as text (^nor-pn0b).

    [Error rejection] names the first disqualifying finding in the provider's item order,
    after the status: [`Not_completed status], [`Tool_continuation call], [`Refusal text]
    or [`Other kind]. A completed reply with no output items at all is [Ok ""]: the
    absence of disqualifiers is not a claim that the reply said anything. Pure and
    synchronous: it performs no I/O and registers no finalizer. *)

val create :
  http:Eta_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Eta_observability.Logger.t ->
  api_key:Eta_observability.Redact.t ->
  ?endpoint:string ->
  deadline:Eta.Duration.t ->
  request ->
  (response, Eta_ai.Error.t) result
(** One non-streaming call to [endpoint]. The caller's [deadline] bounds the whole call;
    cancellation closes the HTTP socket and no finalizer is registered. *)
