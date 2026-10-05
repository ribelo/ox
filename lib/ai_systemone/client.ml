let default_endpoint = "https://openrouter.ai/api/v1/systemone"
let typesafe_endpoint = "https://api.typesafe.ai/v1/systemone"

type t =
  | T :
      'clock Eio.Time.clock
      * Ox_http.Client.t
      * Ox_observability.Logger.t
      * string
      * Ox_observability.Redact.t
      * string
      * Ox.Duration.t
      * int
      * Ox_ai.Transport.replay_policy
      -> t

let create ~http ~clock ~logger ?(endpoint = default_endpoint) ~api_key ~model
    ?(timeout = Ox_ai.Transport.default_timeout)
    ?(max_request_bytes = Ox_ai.Transport.default_max_request_bytes)
    ?(replay_policy = Ox_ai.Transport.Never_replay) () =
  T
    ( clock,
      http,
      logger,
      endpoint,
      api_key,
      model,
      timeout,
      max_request_bytes,
      replay_policy )

let answer name (response : Codecs.response) = List.assoc_opt name response.Codecs.answers

let evaluate
    (T
       ( clock,
         http,
         logger,
         endpoint,
         api_key,
         model,
         timeout,
         max_request_bytes,
         replay_policy )) ~deadline ~state ~questions =
  let body =
    Ox_ai.Transport.bytes_of_json
      (Codecs.yojson_of_request { Codecs.model; state; questions })
  in
  match
    Ox_ai.Transport.post_json ~http ~clock ~logger ~timeout ~max_request_bytes
      ~replay_policy ~endpoint
      ~authorization:(Ox_ai.Bearer.header ~api_key)
      ~body ~deadline ()
  with
  | Error error -> Error error
  | Ok response -> (
      let raw = Bytes.to_string response.Ox_ai.Transport.body in
      match Ox_json.parse raw with
      | Error (`Malformed message) ->
          (* The text is carried as the issue's value: pp_issue bounds what it renders. *)
          Error
            (`Invalid_response
               { path = ""; message = "malformed JSON: " ^ message; got = `String raw })
      | Error (`Too_large { Ox_json.limit; length }) ->
          Error (`Input_too_large { Ox_json.limit; length })
      | Ok json -> (
          match Codecs.t_of_response json with
          | Error message -> Error (`Invalid_response { path = ""; message; got = json })
          | Ok decoded ->
              if not (String.equal decoded.Codecs.model model) then
                Error (`Model_mismatch { expected = model; got = decoded.Codecs.model })
              else (
                Ox_observability.Logger.debug logger
                  ~fields:
                    [
                      ("model", Ox_observability.Logger.String decoded.Codecs.model);
                      ( "input_tokens",
                        Ox_observability.Logger.Int decoded.Codecs.usage.input_tokens );
                      ( "output_tokens",
                        Ox_observability.Logger.Int decoded.Codecs.usage.output_tokens );
                      ("cost", Ox_observability.Logger.Float decoded.Codecs.usage.cost);
                      ( "request_id",
                        Ox_observability.Logger.String
                          (match decoded.Codecs.id with Some id -> id | None -> "") );
                    ]
                  "systemone";
                Ok decoded)))
