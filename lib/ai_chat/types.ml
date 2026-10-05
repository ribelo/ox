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

(** Ordered request content; image URLs are passed through without fetching. ^nimg-4k7p *)
type content_part = Text of string | Image_url of string

(* Only the string-or-array choice needs a custom codec. The part objects stay derived
   wire records (ADR-0008), so required members and their types remain fail-closed.
   The all-text string form follows v1's pure chat_content_json. ^nimg-r6w1 ^nimg-t9q3 *)
module Content = struct
  type t = content_part list
  type text_kind = Text_kind [@json.name "text"] [@@deriving yojson]
  type image_kind = Image_kind [@json.name "image_url"] [@@deriving yojson]

  type text_part = { kind : text_kind; [@json.key "type"] text : string }
  [@@deriving yojson]

  type image_url = { url : string } [@@deriving yojson]

  type image_part = { kind : image_kind; [@json.key "type"] image_url : image_url }
  [@@deriving yojson]

  let yojson_of_part = function
    | Text text -> yojson_of_text_part { kind = Text_kind; text }
    | Image_url url -> yojson_of_image_part { kind = Image_kind; image_url = { url } }

  let yojson_of_t parts =
    if List.exists (function Image_url _ -> true | Text _ -> false) parts then
      `List (List.map yojson_of_part parts)
    else
      `String
        (String.concat ""
           (List.filter_map
              (function Text text -> Some text | Image_url _ -> None)
              parts))

  let part_of_yojson = function
    | `Assoc fields as json -> (
        match List.assoc_opt "type" fields with
        | Some (`String "text") ->
            Result.map (fun part -> Text part.text) (text_part_of_yojson json)
        | Some (`String "image_url") ->
            Result.map
              (fun part -> Image_url part.image_url.url)
              (image_part_of_yojson json)
        | _ -> Error "type: expected text or image_url")
    | _ -> Error "expected a content-part object"

  let t_of_yojson = function
    | `String text -> Ok [ Text text ]
    | `List parts ->
        let rec decode index acc = function
          | [] -> Ok (List.rev acc)
          | json :: rest -> (
              match part_of_yojson json with
              | Ok part -> decode (index + 1) (part :: acc) rest
              | Error message -> Error (Printf.sprintf "[%d].%s" index message))
        in
        decode 0 [] parts
    | _ -> Error "expected a string or content-part array"
end

type message = { role : role; content : Content.t }
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** A request message carries parts; all-text content still writes a string. ^nimg-4k7p *)

let text_message role text : message = { role; content = [ Text text ] }

let png_data_url png =
  "data:image/png;base64," ^ Ox_http.Ws_base64.encode_string (Bytes.to_string png)

let image_png png = Image_url (png_data_url png)

type reply_message = { role : role; content : string }
[@@deriving yojson] [@@yojson.allow_extra_fields]
(** Reply content stays a required string: null, missing or array content is refused,
    never defaulted or flattened. ^nchat-wtog ^nimg-c8v5 *)

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

type choice = { message : reply_message; finish_reason : string option }
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
