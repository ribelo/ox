type request = {
  model : string;
  filename : string;
  wav : bytes;
  language : string option;
  prompt : string option;
  temperature : float option;
}

type reply = { text : string option } [@@deriving yojson] [@@yojson.allow_extra_fields]

let default_endpoint = "https://openrouter.ai/api/v1/audio/transcriptions"
let default_max_request_bytes = 8 * 1024 * 1024
let max_request_bytes = default_max_request_bytes
let boundary = "eta-ai-wav-boundary-59f3201f"
let invalid message = Common.invalid message `Null

let body ?(max_request_bytes = default_max_request_bytes) request =
  if max_request_bytes <= 0 then
    invalid_arg "Eta_ai_openrouter.Audio.body: max_request_bytes must be positive"
  else if
    request.model = ""
    || Bytes.length request.wav = 0
    || String.contains request.filename '\r'
    || String.contains request.filename '\n'
    || String.contains request.filename '"'
    || request.filename = ""
  then invalid "invalid model, filename or WAV"
  else if
    match request.temperature with Some f -> not (Float.is_finite f) | None -> false
  then invalid "non-finite temperature"
  else
    let buffer = Buffer.create (Bytes.length request.wav + 512) in
    let part name value =
      Buffer.add_string buffer
        ("--" ^ boundary ^ "\r\nContent-Disposition: form-data; name=\"" ^ name
       ^ "\"\r\n\r\n");
      Buffer.add_string buffer value;
      Buffer.add_string buffer "\r\n"
    in
    part "model" request.model;
    Option.iter (part "language") request.language;
    Option.iter (part "prompt") request.prompt;
    Option.iter (fun t -> part "temperature" (string_of_float t)) request.temperature;
    Buffer.add_string buffer
      ("--" ^ boundary ^ "\r\nContent-Disposition: form-data; name=\"file\"; filename=\""
     ^ request.filename ^ "\"\r\nContent-Type: audio/wav\r\n\r\n");
    Buffer.add_bytes buffer request.wav;
    Buffer.add_string buffer ("\r\n--" ^ boundary ^ "--\r\n");
    let value = Buffer.contents buffer in
    if String.length value > max_request_bytes then
      Error
        (`Input_too_large
           { Eta_json.limit = max_request_bytes; length = String.length value })
    else Ok (Bytes.of_string value)

let decode json =
  match reply_of_yojson json with
  | Error message -> Common.invalid message json
  | Ok { text = Some text } when String.trim text <> "" -> Ok (String.trim text)
  | Ok _ -> Common.invalid ~path:"text" "missing transcription text" json

let create ~http ~api_key ?(endpoint = default_endpoint) ?max_request_bytes ~deadline
    request =
  let limit = Option.value ~default:default_max_request_bytes max_request_bytes in
  match body ?max_request_bytes request with
  | Error _ as error -> error
  | Ok body -> (
      let headers =
        Eta_ai.Bearer.header ~api_key
        @ [ ("Content-Type", "multipart/form-data; boundary=" ^ boundary) ]
      in
      match
        Eta_http.Client.request http ~method_:"POST" ~url:endpoint ~headers ~body
          ~deadline ~max_body_bytes:Eta_ai.Transport.default_max_response_bytes ()
      with
      | Error (`Timeout | `Idle_timeout) -> Error `Timeout
      | Error `Body_too_large ->
          Common.invalid "transcription reply exceeds byte limit" `Null
      | Error _ ->
          Error
            (`Unavailable
               {
                 message = "transcription transport failure";
                 retryable = true;
                 retry_after = None;
               })
      | Ok { status = 401; _ } ->
          Error (`Authentication "transcription authentication failed")
      | Ok { status = 413; _ } ->
          Error (`Input_too_large { Eta_json.limit; length = Bytes.length body })
      | Ok { status; _ } when status < 200 || status >= 300 ->
          Error
            (`Unavailable
               {
                 message = Printf.sprintf "transcription HTTP %d" status;
                 retryable = status = 429 || status = 529;
                 retry_after = None;
               })
      | Ok response -> (
          match Common.decode (Bytes.to_string response.body) with
          | Error _ as error -> error
          | Ok json -> decode json))
