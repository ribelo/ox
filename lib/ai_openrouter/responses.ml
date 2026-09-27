(* OpenRouter's Responses input_audio shape follows v1:openai_codec/content.ml. *)
type schema = { name : string; schema : Eta_json.t; strict : bool option }
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
  type t = Eta_json.t

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

type response = {
  id : string option;
  model : string option;
  status : string;
  text : string;
}

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

let obj = Eta_json.object_
let s value = Some (Eta_json.string value)

let format_json = function
  | Text -> obj [ ("type", s "text") ]
  | Json_object -> obj [ ("type", s "json_object") ]
  | Json_schema { name; schema; strict } ->
      obj
        [
          ("type", s "json_schema");
          ("name", s name);
          ("schema", Some schema);
          ("strict", Option.map Eta_json.bool strict);
        ]

let encode (request : request) =
  let audio =
    obj
      [
        ("type", s "input_audio");
        ( "input_audio",
          Some (obj [ ("data", s (base64 request.wav)); ("format", s "wav") ]) );
      ]
  in
  let text = obj [ ("type", s "input_text"); ("text", s request.prompt) ] in
  let input =
    Eta_json.array
      [ obj [ ("role", s "user"); ("content", Some (Eta_json.array [ text; audio ])) ] ]
  in
  obj
    [
      ("model", s request.model);
      ("input", Some input);
      ("stream", Some (Eta_json.bool false));
      ("temperature", Option.bind request.temperature Eta_json.float);
      ( "text",
        Option.map
          (fun format -> obj [ ("format", Some (format_json format)) ])
          request.text_format );
      ( "reasoning",
        Option.map (fun effort -> obj [ ("effort", s effort) ]) request.reasoning_effort
      );
    ]

(* v1:openai_codec/responses.ml output_text: only message content and output_text.
   Dynamic output items use Of_json so malformed relevant content is not silently lost. *)
let field name decoder json = Eta_json.Of_json.field name decoder json
let invalid_issue result = Result.map_error (fun issue -> `Invalid_response issue) result

let output_text item =
  match Eta_json.string_member "type" item with
  | Some "message" | None -> (
      let open Eta_json.Of_json in
      match
        field "content"
          (list (fun part ->
               match Eta_json.string_member "type" part with
               | Some "output_text" | None -> field "text" string part
               | Some _ -> Ok ""))
          item
        |> invalid_issue
      with
      | Error _ as error -> error
      | Ok texts -> Ok (List.filter (fun text -> text <> "") texts))
  | Some "output_text" ->
      field "text" Eta_json.Of_json.string item
      |> invalid_issue
      |> Result.map (fun text -> [ text ])
  | Some _ -> Ok []

let decode json =
  match header_of_yojson json with
  | Error message -> Common.invalid message json
  | Ok header ->
      if header.status = "failed" then
        Common.invalid ~path:"status" "provider failed" json
      else
        let rec collect acc = function
          | [] ->
              Ok
                {
                  id = header.id;
                  model = header.model;
                  status = header.status;
                  text = String.concat "" (List.rev acc);
                }
          | item :: rest -> (
              match output_text item with
              | Error _ as error -> error
              | Ok texts -> collect (List.rev_append texts acc) rest)
        in
        collect [] header.output

let create ~http ~clock ~logger ~api_key ?(endpoint = default_endpoint) ~deadline
    (request : request) =
  if request.model = "" || request.prompt = "" || Bytes.length request.wav = 0 then
    Common.invalid "model, prompt and WAV must be nonempty" (encode request)
  else
    match request.temperature with
    | Some f when not (Float.is_finite f) -> Common.invalid "non-finite temperature" `Null
    | _ -> (
        match
          Common.post ~http ~clock ~logger ~api_key ~endpoint ~deadline (encode request)
        with
        | Error _ as error -> error
        | Ok json -> decode json)
