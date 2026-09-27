(** Indexed float embeddings for nema. Input shape and decoder are pure; create is bounded
    by deadline and its HTTP socket closes on cancellation. *)
type input = Text of string | Texts of string list

type request = { model : string; input : input; dimensions : int option }
type item = { index : int; vector : float list }
type response = { embeddings : item list; input_tokens : int option }

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
