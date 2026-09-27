val invalid : ?path:string -> string -> Eta_json.t -> ('a, Eta_ai.Error.t) result
(** Shared JSON request/response boundary. Each call closes its own HTTP socket on
    success, failure or cancellation; no finalizer is registered here. *)

val decode : string -> (Eta_json.t, Eta_ai.Error.t) result

val post :
  http:Eta_http.Client.t ->
  clock:_ Eio.Time.clock ->
  logger:Eta_observability.Logger.t ->
  api_key:Eta_observability.Redact.t ->
  endpoint:string ->
  deadline:Eta.Duration.t ->
  Eta_json.t ->
  (Eta_json.t, Eta_ai.Error.t) result
