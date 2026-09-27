type request = {
  model : string;
  filename : string;
  wav : bytes;
  language : string option;
  prompt : string option;
  temperature : float option;
}
(** Bounded WAV multipart transcription for Pie. The HTTP request owns its socket and
    closes it on completion or cancellation; this module registers no finalizer. *)

val default_endpoint : string
val max_request_bytes : int
val body : request -> (bytes, Eta_ai.Error.t) result
val decode : Eta_json.t -> (string, Eta_ai.Error.t) result

val create :
  http:Eta_http.Client.t ->
  api_key:Eta_observability.Redact.t ->
  ?endpoint:string ->
  deadline:Eta.Duration.t ->
  request ->
  (string, Eta_ai.Error.t) result
