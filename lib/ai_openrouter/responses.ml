(* OpenRouter's Responses input_audio shape follows v1:openai_codec/content.ml. *)
type schema = { name : string; schema : Ox_json.t; strict : bool option }
type format = Text | Json_object | Json_schema of schema

type request = {
  model : string;
  prompt : string;
  wav : bytes;
  temperature : float option;
  text_format : format option;
  reasoning_effort : string option;
}

module Raw = struct
  type t = Ox_json.t

  let yojson_of_t json = json
  let t_of_yojson json = Ok json
end

type header = {
  id : string option;
  model : string option;
  status : string;
  output : Raw.t list;
}
[@@deriving yojson] [@@yojson.allow_extra_fields]

type audio_format = Wav | Mp3

type text_request = {
  model : string;
  instructions : string;
  input : string;
  temperature : float option;
  text_format : format option;
  reasoning_effort : string option;
}

type function_call = { name : string option; call_id : string option }

type output =
  | Output_text of string
  | Function_call of function_call
  | Refusal of string
  | Other of string

type response = {
  id : string option;
  model : string option;
  status : string;
  text : string;
  output : output list;
}

type rejection =
  [ `Not_completed of string
  | `Tool_continuation of function_call
  | `Refusal of string
  | `Other of string ]

let default_endpoint = "https://openrouter.ai/api/v1/responses"
let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let base64 bytes =
  let len = Bytes.length bytes in
  let out = Buffer.create ((len + 2) / 3 * 4) in
  let char n = table.[n land 63] in
  for i = 0 to ((len + 2) / 3) - 1 do
    let p = i * 3 in
    let a = Bytes.get_uint8 bytes p in
    let b = if p + 1 < len then Bytes.get_uint8 bytes (p + 1) else 0 in
    let c = if p + 2 < len then Bytes.get_uint8 bytes (p + 2) else 0 in
    Buffer.add_char out (char (a lsr 2));
    Buffer.add_char out (char (((a land 3) lsl 4) lor (b lsr 4)));
    Buffer.add_char out
      (if p + 1 < len then char (((b land 15) lsl 2) lor (c lsr 6)) else '=');
    Buffer.add_char out (if p + 2 < len then char c else '=')
  done;
  Buffer.contents out

let obj = Ox_json.object_
let s value = Some (Ox_json.string value)

let format_json = function
  | Text -> obj [ ("type", s "text") ]
  | Json_object -> obj [ ("type", s "json_object") ]
  | Json_schema { name; schema; strict } ->
      obj
        [
          ("type", s "json_schema");
          ("name", s name);
          ("schema", Some schema);
          ("strict", Option.map Ox_json.bool strict);
        ]

let input_message parts =
  Ox_json.array [ obj [ ("role", s "user"); ("content", Some (Ox_json.array parts)) ] ]

let input_text text = obj [ ("type", s "input_text"); ("text", s text) ]

let encode_input ~model ?instructions ~input ~temperature ~text_format ~reasoning_effort
    () =
  obj
    [
      ("model", s model);
      ("instructions", Option.map Ox_json.string instructions);
      ("input", Some input);
      ("stream", Some (Ox_json.bool false));
      ("temperature", Option.bind temperature Ox_json.float);
      ( "text",
        Option.map
          (fun format -> obj [ ("format", Some (format_json format)) ])
          text_format );
      ( "reasoning",
        Option.map (fun effort -> obj [ ("effort", s effort) ]) reasoning_effort );
    ]

(* ^oxpie-a4m7: the record's legacy [wav] field remains source-compatible. *)
let encode ?(audio_format = Wav) ?instructions (request : request) =
  let format = match audio_format with Wav -> "wav" | Mp3 -> "mp3" in
  let audio =
    obj
      [
        ("type", s "input_audio");
        ( "input_audio",
          Some (obj [ ("data", s (base64 request.wav)); ("format", s format) ]) );
      ]
  in
  encode_input ~model:request.model ?instructions
    ~input:(input_message [ input_text request.prompt; audio ])
    ~temperature:request.temperature ~text_format:request.text_format
    ~reasoning_effort:request.reasoning_effort ()

(* ^oxpie-d3t9: text and audio calls share framing, decoding and delivery. *)
let encode_text (request : text_request) =
  encode_input ~model:request.model ~instructions:request.instructions
    ~input:(input_message [ input_text request.input ])
    ~temperature:request.temperature ~text_format:request.text_format
    ~reasoning_effort:request.reasoning_effort ()

(* v1:openai_codec/responses.ml reads only message text. This decoder reports every item
   and every message content part with the kind the provider named, so a disqualifying
   item — a tool continuation above all — cannot be silently dropped (^nor-pn0b).
   Malformed relevant content stays an error rather than becoming empty text. *)
let field name decoder json = Ox_json.Of_json.field name decoder json
let invalid_issue result = Result.map_error (fun issue -> `Invalid_response issue) result
let issue path message got = Error { Ox_json.path; message; got }

let text_of part =
  field "text" Ox_json.Of_json.string part |> Result.map (fun text -> Output_text text)

let refusal_of item =
  match (Ox_json.string_member "refusal" item, Ox_json.string_member "text" item) with
  | Some text, _ | None, Some text -> Ok (Refusal text)
  | None, None -> issue "refusal" "refusal without text" item

(* One message content part: the documented [output_text] and [refusal] parts, and any
   other part kind reported instead of dropped. A part without a [type] has always read
   as text; keep that. *)
let part_of part =
  match Ox_json.string_member "type" part with
  | Some "output_text" | None -> text_of part
  | Some "refusal" -> refusal_of part
  | Some kind -> Ok (Other kind)

let outputs_of_item item =
  match Ox_json.string_member "type" item with
  | Some "message" | None -> field "content" (Ox_json.Of_json.list part_of) item
  | Some "output_text" -> text_of item |> Result.map (fun output -> [ output ])
  | Some "refusal" -> refusal_of item |> Result.map (fun output -> [ output ])
  | Some "function_call" ->
      Ok
        [
          Function_call
            {
              name = Ox_json.string_member "name" item;
              call_id = Ox_json.string_member "call_id" item;
            };
        ]
  | Some kind -> Ok [ Other kind ]

let text_of_output output =
  output
  |> List.filter_map (function
    | Output_text text when text <> "" -> Some text
    | _ -> None)
  |> String.concat ""

let decode json =
  match header_of_yojson json with
  | Error message -> Common.invalid message json
  | Ok header -> (
      if header.status = "failed" then
        Common.invalid ~path:"status" "provider failed" json
      else
        let rec collect acc = function
          | [] -> Ok (List.rev acc)
          | item :: rest -> (
              match invalid_issue (outputs_of_item item) with
              | Error _ as error -> error
              | Ok outputs -> collect (List.rev_append outputs acc) rest)
        in
        match collect [] header.output with
        | Error _ as error -> error
        | Ok output ->
            Ok
              {
                id = header.id;
                model = header.model;
                status = header.status;
                text = text_of_output output;
                output;
              })

let deliverable response =
  if response.status <> "completed" then Error (`Not_completed response.status)
  else
    let rec verdict = function
      | [] -> Ok response.text
      | Output_text _ :: rest -> verdict rest
      | Function_call call :: _ -> Error (`Tool_continuation call)
      | Refusal text :: _ -> Error (`Refusal text)
      | Other "reasoning" :: rest -> verdict rest (* ^oxpie-c8r5 *)
      | Other kind :: _ -> Error (`Other kind)
    in
    verdict response.output

let post ~http ~clock ~logger ~api_key ~endpoint ?timeout ?max_request_bytes
    ?max_response_bytes ?response_idle ~deadline ~temperature body =
  match temperature with
  | Some f when not (Float.is_finite f) -> Common.invalid "non-finite temperature" `Null
  | _ -> (
      match
        Common.post ~http ~clock ~logger ~api_key ~endpoint ?timeout ?max_request_bytes
          ?max_response_bytes ?response_idle ~deadline body
      with
      | Error _ as error -> error
      | Ok json -> decode json)

let create ~http ~clock ~logger ~api_key ?(endpoint = default_endpoint) ?audio_format
    ?instructions ?timeout ?max_request_bytes ?max_response_bytes ?response_idle ~deadline
    (request : request) =
  let body = encode ?audio_format ?instructions request in
  if request.model = "" || request.prompt = "" || Bytes.length request.wav = 0 then
    Common.invalid "model, prompt and audio must be nonempty" body
  else
    post ~http ~clock ~logger ~api_key ~endpoint ?timeout ?max_request_bytes
      ?max_response_bytes ?response_idle ~deadline ~temperature:request.temperature body

let create_text ~http ~clock ~logger ~api_key ?(endpoint = default_endpoint) ?timeout
    ?max_request_bytes ?max_response_bytes ?response_idle ~deadline
    (request : text_request) =
  let body = encode_text request in
  if request.model = "" || request.instructions = "" || request.input = "" then
    Common.invalid "model, instructions and input must be nonempty" body
  else
    post ~http ~clock ~logger ~api_key ~endpoint ?timeout ?max_request_bytes
      ?max_response_bytes ?response_idle ~deadline ~temperature:request.temperature body
