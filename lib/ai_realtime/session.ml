type t = Ox_http.Ws_client.t
type error = [ Ox_http.Ws_client.error | `Invalid_event of Ox_json.issue ]
type event = { kind : string; [@json.key "type"] raw : Ox_json.t }

let connect ~sw ~net ~clock ~api_key ?(headers = []) ?ca_file ?protocols
    ?(establishment_timeout = Ox.Duration.seconds 10) url =
  Ox_http.Ws_client.connect ~sw ~net ~clock ?ca_file ?protocols
    ~headers:(Ox_ai.Bearer.header ~api_key @ headers)
    ~establishment_timeout url

let send t json = Ox_http.Ws_client.send_text t (Ox_json.to_string json)

let decode raw =
  match Ox_json.parse raw with
  | Error _ ->
      Error
        (`Invalid_event
           { Ox_json.path = ""; message = "malformed JSON event"; got = `String raw })
  | Ok json -> (
      match Ox_json.string_member "type" json with
      | None ->
          Error
            (`Invalid_event
               { Ox_json.path = "type"; message = "missing event type"; got = json })
      | Some kind -> Ok { kind; raw = json })

let receive t =
  match Ox_http.Ws_client.receive t with
  | Error ws_error -> Error (ws_error :> error)
  | Ok (`Binary _) ->
      Error (`Invalid_event { Ox_json.path = ""; message = "binary event"; got = `Null })
  | Ok (`Text raw) -> decode raw

let close = Ox_http.Ws_client.close
