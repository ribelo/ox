(** Indexed float embeddings for nema. Input shape and decoder are pure; create is bounded
    by deadline and its HTTP socket closes on cancellation. *)
type input = Text of string | Texts of string list

type request = { model : string; input : input; dimensions : int option }
type item = { index : int; vector : float list }
type response = { embeddings : item list; input_tokens : int option }

val default_endpoint : string
val encode : request -> Ox_json.t
val decode : Ox_json.t -> (response, Ox_ai.Error.t) result

val create :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  api_key:Ox_observability.Redact.t ->
  ?endpoint:string ->
  ?timeout:Ox.Duration.t ->
  ?max_response_bytes:int ->
  ?max_attempts:int ->
  deadline:Ox.Duration.t ->
  request ->
  (response, Ox_ai.Error.t) result
(** [timeout] (one attempt's read, default 10 s), [max_response_bytes] and [max_attempts]
    are {!Ox_ai.Transport.post_json}'s: a batch reply larger than 1 MiB needs a larger
    bound, and a caller with its own retry schedule asks for one attempt. ^nai-97as
    ^nai-337c *)
