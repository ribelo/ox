(* The chat wire types the deriver can express (ADR-0008: types are the schema), in both
   directions: the request this client writes and the reply it reads.

   Every reply declaration carries [@@yojson.allow_extra_fields]. The endpoint is
   OpenAI-compatible, not OpenAI: an answer carries members this client does not model
   (`object`, `created`, `index`, `logprobs`, `provider`, `system_fingerprint`), and a
   member nobody reads is not a corrupt answer. The members the client acts on are still
   required, and a missing or wrongly typed one is refused with its path (^nchat-wtog).

   The request's optional members need no help: the deriver omits a [None] field, so a call
   without [max_tokens], [json_object] or [reasoning] sends no such member at all
   (^nchat-6kd8 ^nchat-02vr). *)

(** Who speaks a message, written as the API's lowercase word. [Assistant] is the role a
    reply's message carries, so a reply that names another role is refused. *)
type role =
  | System [@json.name "system"]
  | User [@json.name "user"]
  | Assistant [@json.name "assistant"]
[@@deriving yojson]

type message = { role : role; content : string }
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** One message: its speaker and its text. `content` is required and a string — a reply
    whose content is `null` or absent is an [`Invalid_response], never an empty string
    (^nchat-wtog). *)

type usage = {
  prompt_tokens : int;
  completion_tokens : int;
  total_tokens : int;
  cost : float option;
}
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** What the completion cost. The three token counts are required, so a reply without them
    is refused rather than read as zero. [cost] is the provider's own accounting in USD,
    when it reports one: OpenRouter sends it beside the token counts, and a chat endpoint
    is OpenAI-compatible, not OpenRouter, so a server that reports only tokens is not
    sending a broken reply — an absent member (or a `null`) reads [None], never [0.]
    (^nchat-qu3j). A cost that is present and not a number is refused with its path, like
    every other wrongly typed member (^nchat-wtog). OpenRouter's `cost_details` is a
    member nobody reads and is ignored. *)

(** The one response format this client asks for. ^nchat-02vr *)
type response_format_kind = Json_object [@json.name "json_object"] [@@deriving yojson]

type response_format = { kind : response_format_kind [@json.key "type"] }
[@@deriving yojson]
(** [{"type": "json_object"}]: sent only when the caller requires JSON. *)

type reasoning = { enabled : bool option; effort : string option } [@@deriving yojson]
(** OpenRouter's reasoning control: [{"enabled": false}] or [{"effort": "low"}]. One of
    the two members is set; a call that says nothing about reasoning sends no member at
    all. ^nchat-6kd8 *)

type request = {
  model : string;
  messages : message list;
  max_tokens : int option;
  response_format : response_format option;
  reasoning : reasoning option;
}
[@@deriving yojson]
(** The request body, exactly as `POST /chat/completions` documents it: the model, the
    messages, and the optional cap, format and reasoning control. *)

type choice = { message : message; finish_reason : string option }
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** One completion: its message and why generation stopped (`null` reads as [None]). *)

type response = {
  id : string option;
  model : string;
  choices : choice list;
  usage : usage;
}
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** The reply. `choices` may be empty on the wire; {!Codecs.completion_of_response}
    refuses that, because a reply without a completion is not an answer. *)
