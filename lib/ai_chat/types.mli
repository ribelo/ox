(** The chat wire types (ADR-0008: types are the schema), in both directions.

    The request is exactly what `POST /chat/completions` documents — model, messages, and
    the optional cap, response format and reasoning control — and the reply is the first
    choice's message plus the usage, read with no default. Reply declarations accept
    members this client does not model, because the endpoint is OpenAI-compatible and not
    OpenAI; the members the client acts on are required (^nchat-wtog).

    Cancellation and finalizers: every type here is plain data and every codec and
    constructor is pure and synchronous. Suspension: never suspends; only constructs,
    encodes or decodes OCaml values. Cancellation: not a cancellation point; no Eio
    operation is performed. Finalizers: none are registered; no resource is owned.
    Locking: no lock is acquired.

    ^nchat-dys0 ^nchat-6kd8 ^nchat-02vr ^nimg-4k7p ^nimg-r6w1 *)

(** Who speaks a message: the API's `system`, `user` and `assistant`, written as the
    lowercase word the endpoint expects. *)
type role = System | User | Assistant

(** Request content in order. [Image_url url] carries an HTTPS or data URL as supplied;
    this client neither fetches nor validates it. ^nimg-4k7p *)
type content_part = Text of string | Image_url of string

type message = { role : role; content : content_part list }
(** A request message. All-text parts concatenate without separators into the original
    string wire form (the empty list writes [""]). Any image selects an ordered array of
    text and image-URL objects instead. ^nimg-4k7p ^nimg-t9q3 *)

val text_message : role -> string -> message
(** [text_message role text] is [{ role; content = [Text text] }], the one-line builder
    for a text-only caller. Suspension: never suspends; only constructs plain data.
    Cancellation: not a cancellation point; no Eio operation is performed. Finalizers:
    none are registered; no resource is owned. Locking: no lock is acquired. ^nimg-t9q3 *)

val png_data_url : bytes -> string
(** [png_data_url png] prefixes the RFC 4648 basic base64 of [png] with
    ["data:image/png;base64,"]. Bytes are copied, not modified, and PNG headers are not
    inspected. Suspension: never suspends; byte encoding is synchronous. Cancellation: not
    a cancellation point; no Eio operation is performed. Finalizers: none are registered;
    no resource is owned. Locking: no lock is acquired. ^nimg-b2u8 *)

val image_png : bytes -> content_part
(** [image_png png] is [Image_url (png_data_url png)]. Suspension: never suspends; only
    encodes bytes and constructs plain data. Cancellation: not a cancellation point; no
    Eio operation is performed. Finalizers: none are registered; no resource is owned.
    Locking: no lock is acquired. ^nimg-b2u8 *)

type reply_message = { role : role; content : string }
(** A reply message: [content] is required and a string. Missing, null or array content is
    refused rather than flattened or defaulted. ^nchat-wtog ^nimg-c8v5 *)

type usage = {
  prompt_tokens : int;
  completion_tokens : int;
  total_tokens : int;
  cost : float option;
}
(** What the completion cost: the three token counts, all required, and the provider's own
    cost in USD when it reports one (^nchat-qu3j). `cost` is never required — a server
    that reports only tokens is not sending a broken reply, so an absent member (or a
    `null`) reads `None`, never `0.` — while a cost that is present and not a number is
    refused with its path, like every other wrongly typed member (^nchat-wtog). *)

(** The one response format this client asks for. *)
type response_format_kind = Json_object

type response_format = { kind : response_format_kind }
(** [{"type": "json_object"}], on the wire. *)

type reasoning = { enabled : bool option; effort : string option }
(** OpenRouter's reasoning control; one member is set. *)

type request = {
  model : string;
  messages : message list;
  max_tokens : int option;
  response_format : response_format option;
  reasoning : reasoning option;
}
(** The request body. An absent option is an absent member. *)

type choice = { message : reply_message; finish_reason : string option }
(** One completion. *)

type response = {
  id : string option;
  model : string;
  choices : choice list;
  usage : usage;
}
(** The reply. *)

val yojson_of_request : request -> Yojson.Safe.t
(** [yojson_of_request request] is the compact-encodable JSON object the client sends: an
    absent [max_tokens], [response_format] or [reasoning] is an absent member. Each
    message uses the string-or-array content form described by {!message}. ^nimg-4k7p
    ^nimg-t9q3 *)

val request_of_yojson : Yojson.Safe.t -> (request, string) result
(** [request_of_yojson json] reads a request back. String content becomes one [Text] part;
    array content preserves part order and boundaries. All-text lists therefore round-trip
    as their concatenated string, not their original segmentation. Unknown request or part
    members, missing required members and wrong types are refused with the offending path;
    message-level extra members remain ignored. ^nimg-r6w1 *)

val response_of_yojson : Yojson.Safe.t -> (response, string) result
(** [response_of_yojson json] reads a reply fail-closed: `model`, `choices` and `usage`
    are required, a choice's `message.content` must be a string, and a member this type
    does not name is ignored — the endpoint is OpenAI-compatible, not OpenAI. A failure
    carries the path of the offending value. *)
