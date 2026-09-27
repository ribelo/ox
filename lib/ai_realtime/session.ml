type t = Eta_http.Ws_client.t
type error = [ Eta_http.Ws_client.error | `Invalid_event of Eta_json.issue ]
type event = { kind : string; [@json.key "type"] raw : Eta_json.t }

let connect ~sw ~net ~clock ~api_key ?(headers = []) ?ca_file ?protocols
    ?(establishment_timeout = Eta.Duration.seconds 10) url =
  Eta_http.Ws_client.connect ~sw ~net ~clock ?ca_file ?protocols
    ~headers:(Eta_ai.Bearer.header ~api_key @ headers)
    ~establishment_timeout url

let send t json = Eta_http.Ws_client.send_text t (Eta_json.to_string json)

let decode raw =
  match Eta_json.parse raw with
  | Error _ ->
      Error
        (`Invalid_event
           { Eta_json.path = ""; message = "malformed JSON event"; got = `String raw })
  | Ok json -> (
      match Eta_json.string_member "type" json with
      | None ->
          Error
            (`Invalid_event
               { Eta_json.path = "type"; message = "missing event type"; got = json })
      | Some kind -> Ok { kind; raw = json })

let receive t =
  match Eta_http.Ws_client.receive t with
  | Error ws_error -> Error (ws_error :> error)
  | Ok (`Binary _) ->
      Error (`Invalid_event { Eta_json.path = ""; message = "binary event"; got = `Null })
  | Ok (`Text raw) -> decode raw

let close = Eta_http.Ws_client.close
