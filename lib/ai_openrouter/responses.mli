type schema = { name : string; schema : Eta_json.t; strict : bool option }
(** Pie Responses text plus input_audio/WAV. The call is bounded by the supplied deadline;
    cancellation closes the HTTP socket, with no additional finalizer. *)

type format = Text | Json_object | Json_schema of schema

type request = {
  model : string;
  prompt : string;
  wav : bytes;
  temperature : float option;
  text_format : format option;
  reasoning_effort : string option;
}

type response = {
  id : string option;
  model : string option;
  status : string;
  text : string;
}

val default_endpoint : string
val encode : request -> Eta_json.t
val decode : Eta_json.t -> (response, Eta_ai.Error.t) result

val create :
  http:Eta_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Eta_observability.Logger.t ->
  api_key:Eta_observability.Redact.t ->
  ?endpoint:string ->
  deadline:Eta.Duration.t ->
  request ->
  (response, Eta_ai.Error.t) result
