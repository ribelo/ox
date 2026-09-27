let invalid ?(path = "") message got =
  Error (`Invalid_response { Eta_json.path; message; got })

let decode raw =
  match Eta_json.parse raw with
  | Ok json -> Ok json
  | Error (`Malformed message) -> invalid ("malformed JSON: " ^ message) (`String raw)
  | Error (`Too_large bound) -> Error (`Input_too_large bound)

let post ~http ~clock ~logger ~api_key ~endpoint ~deadline body =
  let body = Eta_ai.Transport.bytes_of_json body in
  match
    Eta_ai.Transport.post_json ~http ~clock ~logger ~endpoint
      ~authorization:(Eta_ai.Bearer.header ~api_key)
      ~body ~deadline ()
  with
  | Error _ as error -> error
  | Ok response -> decode (Bytes.to_string response.Eta_ai.Transport.body)
