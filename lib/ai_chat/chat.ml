let default_endpoint = "https://openrouter.ai/api/v1/chat/completions"

type t =
  | T :
      'clock Eio.Time.clock
      * Ox_http.Client.t
      * Ox_observability.Logger.t
      * string
      * Ox_observability.Redact.t
      * Ox.Duration.t
      * int
      -> t

let create ~http ~clock ~logger ?(endpoint = default_endpoint) ~api_key
    ?(timeout = Ox_ai.Transport.default_timeout)
    ?(max_request_bytes = Ox_ai.Transport.default_max_request_bytes) () =
  T (clock, http, logger, endpoint, api_key, timeout, max_request_bytes)

(* The caller's control, in the spelling [complete] takes, becomes the wire record: the
   two forms set different members, and the third state — the caller saying nothing — is
   the option's [None], so no member is written at all. *)
let wire_reasoning : [< `Disabled | `Effort of string ] -> Types.reasoning = function
  | `Disabled -> { Types.enabled = Some false; effort = None }
  | `Effort effort -> { Types.enabled = None; effort = Some effort }

let complete (T (clock, http, logger, endpoint, api_key, timeout, max_request_bytes))
    ~deadline ~model ~messages ?max_tokens ?(json_object = false) ?reasoning () =
  let request =
    {
      Types.model;
      messages;
      max_tokens;
      response_format =
        (if json_object then Some { Types.kind = Types.Json_object } else None);
      reasoning = Option.map wire_reasoning reasoning;
    }
  in
  let body = Ox_ai.Transport.bytes_of_json (Types.yojson_of_request request) in
  match
    Ox_ai.Transport.post_json ~http ~clock ~logger ~timeout ~max_request_bytes ~endpoint
      ~authorization:(Ox_ai.Bearer.header ~api_key)
      ~body ~deadline ()
  with
  | Error error -> Error error
  | Ok response -> (
      let raw = Bytes.to_string response.Ox_ai.Transport.body in
      match Ox_json.parse raw with
      | Error (`Malformed message) ->
          Error
            (`Invalid_response
               { path = ""; message = "malformed JSON: " ^ message; got = `String raw })
      | Error (`Too_large { Ox_json.limit; length }) ->
          Error (`Input_too_large { Ox_json.limit; length })
      | Ok json -> (
          match Types.response_of_yojson json with
          | Error message -> Error (`Invalid_response { path = ""; message; got = json })
          | Ok reply -> (
              match Codecs.completion_of_response reply with
              | Error message ->
                  Error (`Invalid_response { path = "choices"; message; got = json })
              | Ok completion ->
                  let usage = completion.Codecs.usage in
                  (* The provider's own cost is logged when it reports one (^nchat-qu3j).
                     A reply that reports no cost says nothing about spend, so the line
                     carries no [cost] field rather than a zero, which would read as
                     "free". *)
                  let cost_fields =
                    match usage.Types.cost with
                    | Some cost -> [ ("cost", Ox_observability.Logger.Float cost) ]
                    | None -> []
                  in
                  Ox_observability.Logger.debug logger
                    ~fields:
                      ([
                         ("model", Ox_observability.Logger.String completion.Codecs.model);
                         ("prompt_tokens", Ox_observability.Logger.Int usage.prompt_tokens);
                         ( "completion_tokens",
                           Ox_observability.Logger.Int usage.completion_tokens );
                         ("total_tokens", Ox_observability.Logger.Int usage.total_tokens);
                       ]
                      @ cost_fields
                      @ [
                          ( "request_id",
                            Ox_observability.Logger.String
                              (match completion.Codecs.id with
                              | Some id -> id
                              | None -> "") );
                        ])
                    "chat";
                  Ok completion)))
