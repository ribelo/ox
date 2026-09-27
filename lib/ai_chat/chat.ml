let default_endpoint = "https://openrouter.ai/api/v1/chat/completions"

type t =
  | T :
      'clock Eio.Time.clock
      * Eta_http.Client.t
      * Eta_observability.Logger.t
      * string
      * Eta_observability.Redact.t
      * Eta.Duration.t
      * int
      -> t

let create ~http ~clock ~logger ?(endpoint = default_endpoint) ~api_key
    ?(timeout = Eta_ai.Transport.default_timeout)
    ?(max_request_bytes = Eta_ai.Transport.default_max_request_bytes) () =
  T (clock, http, logger, endpoint, api_key, timeout, max_request_bytes)

(* The caller's control, in the spelling [complete] takes, becomes the wire record: the
   two forms name different members, and {} is not one of them. *)
let wire_reasoning : [< `Disabled | `Effort of string ] -> Types.reasoning = function
  | `Disabled -> { Types.enabled = Some false; effort = None }
  | `Effort effort -> { Types.enabled = None; effort = Some effort }

let complete
    (T (clock, http, logger, endpoint, api_key, timeout, max_request_bytes)) ~deadline
    ~model ~messages ?max_tokens ?(json_object = false) ?reasoning () =
  let request =
    {
      Types.model = model;
      messages;
      max_tokens;
      response_format =
        (if json_object then Some { Types.kind = Types.Json_object } else None);
      reasoning = Option.map wire_reasoning reasoning;
    }
  in
  let body = Eta_ai.Transport.bytes_of_json (Types.yojson_of_request request) in
  match
    Eta_ai.Transport.post_json ~http ~clock ~logger ~timeout ~max_request_bytes
      ~endpoint ~authorization:(Eta_ai.Bearer.header ~api_key) ~body ~deadline ()
  with
  | Error error -> Error error
  | Ok response -> (
      let raw = Bytes.to_string response.Eta_ai.Transport.body in
      match Eta_json.parse raw with
      | Error (`Malformed message) ->
          Error
            (`Invalid_response
               { path = ""; message = "malformed JSON: " ^ message; got = `String raw })
      | Error (`Too_large { Eta_json.limit; length }) ->
          Error (`Input_too_large { Eta_json.limit; length })
      | Ok json -> (
          match Types.response_of_yojson json with
          | Error message -> Error (`Invalid_response { path = ""; message; got = json })
          | Ok reply -> (
              match Codecs.completion_of_response reply with
              | Error message ->
                  Error (`Invalid_response { path = "choices"; message; got = json })
              | Ok completion ->
                  Eta_observability.Logger.debug logger
                    ~fields:
                      [
                        ("model", Eta_observability.Logger.String completion.Codecs.model);
                        ( "prompt_tokens",
                          Eta_observability.Logger.Int
                            completion.Codecs.usage.prompt_tokens );
                        ( "completion_tokens",
                          Eta_observability.Logger.Int
                            completion.Codecs.usage.completion_tokens );
                        ( "total_tokens",
                          Eta_observability.Logger.Int
                            completion.Codecs.usage.total_tokens );
                        ( "request_id",
                          Eta_observability.Logger.String
                            (match completion.Codecs.id with
                            | Some id -> id
                            | None -> "") );
                      ]
                    "chat";
                  Ok completion)))
