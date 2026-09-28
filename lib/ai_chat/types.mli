(** The chat wire types (ADR-0008: types are the schema), in both directions.

    The request is exactly what `POST /chat/completions` documents — model, messages, and
    the optional cap, response format and reasoning control — and the reply is the first
    choice's message plus the usage, read with no default. Reply declarations accept
    members this client does not model, because the endpoint is OpenAI-compatible and not
    OpenAI; the members the client acts on are required (^nchat-wtog).

    Cancellation and finalizers: every type here is plain data and every derived codec is
    pure and synchronous. Decoding suspends on nothing, forks no fiber and registers no
    finalizer.

    ^nchat-dys0 ^nchat-6kd8 ^nchat-02vr *)

(** Who speaks a message: the API's `system`, `user` and `assistant`, written as the
    lowercase word the endpoint expects. *)
type role = System | User | Assistant

type message = { role : role; content : string }
(** One message: its speaker and its text. `content` is required and a string. *)

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

type choice = { message : message; finish_reason : string option }
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
    absent [max_tokens], [response_format] or [reasoning] is an absent member. Pure. *)

val request_of_yojson : Yojson.Safe.t -> (request, string) result
(** [request_of_yojson json] reads a request back. An unknown member, a missing required
    member and a wrongly typed one are refused with the path of the offending value. *)

val response_of_yojson : Yojson.Safe.t -> (response, string) result
(** [response_of_yojson json] reads a reply fail-closed: `model`, `choices` and `usage`
    are required, a choice's `message.content` must be a string, and a member this type
    does not name is ignored — the endpoint is OpenAI-compatible, not OpenAI. A failure
    carries the path of the offending value. *)
