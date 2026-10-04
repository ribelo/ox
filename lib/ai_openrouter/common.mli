(** Cancellation and finalizers: Suspension: may suspend in delegated Ox_ai.Transport and
    Ox_http request I/O. Cancellation: propagates Eio.Cancel.Cancelled from the delegated
    request. Finalizers: the transport owns per-request socket cleanup; this wrapper
    registers no additional hook. Locking: synchronization is delegated to Ox_ai.Transport
    and Ox_http. Cancellation safety: unsafe because progress is lost if the request or
    response is interrupted; the remote request may already have been processed.
    ^nlintd-z5p5 ^nlintd-vneh *)

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
  ?max_request_bytes:int ->
  ?response_idle:Ox.Duration.t ->
  deadline:Ox.Duration.t ->
  Ox_json.t ->
  (Ox_json.t, Ox_ai.Error.t) result
