val invalid : ?path:string -> string -> Ox_json.t -> ('a, Ox_ai.Error.t) result
(** Shared JSON request/response boundary. Each call closes its own HTTP socket on
    success, failure or cancellation; no finalizer is registered here. *)

val decode : string -> (Ox_json.t, Ox_ai.Error.t) result

val post :
  http:Ox_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Ox_observability.Logger.t ->
  api_key:Ox_observability.Redact.t ->
  endpoint:string ->
  ?timeout:Ox.Duration.t ->
  ?max_response_bytes:int ->
  ?max_attempts:int ->
  deadline:Ox.Duration.t ->
  Ox_json.t ->
  (Ox_json.t, Ox_ai.Error.t) result
