type t
(** Codex Realtime JSON session. The caller's switch owns its WebSocket; cancellation or
    switch exit closes the socket, and explicit close sends a close frame. Credentials are
    revealed only when constructing the Authorization header. *)

type error = [ Eta_http.Ws_client.error | `Invalid_event of Eta_json.issue ]
type event = { kind : string; raw : Eta_json.t }

val connect :
  sw:Eio.Switch.t ->
  net:_ Eio.Net.t ->
  clock:_ Eio.Time.clock ->
  api_key:Eta_observability.Redact.t ->
  ?headers:(string * string) list ->
  ?ca_file:string ->
  ?protocols:string list ->
  ?establishment_timeout:Eta.Duration.t ->
  string ->
  (t, Eta_http.Ws_client.error) result
(** [connect ... url] opens [url] with the bearer header built from [api_key]. [headers]
    are appended after it, so the caller's own protocol headers travel unchanged and it
    must not add a second Authorization; [protocols] are the WebSocket subprotocols the
    peer must select from, and [ca_file] adds a PEM trust anchor to the system store.
    [establishment_timeout] bounds DNS, TCP, TLS and the upgrade only. *)

val send : t -> Eta_json.t -> (unit, Eta_http.Ws_client.error) result
(** [send t json] writes [json] as one compact text frame. *)

val decode : string -> (event, error) result
(** [decode raw] reads the event type from [raw]; a non-object or a missing [type] is
    [`Invalid_event]. Pure. *)

val receive : t -> (event, error) result
(** [receive t] waits for the next event. A binary frame is [`Invalid_event]; pings are
    answered by the transport. *)

val close : ?code:int -> ?reason:string -> t -> (unit, Eta_http.Ws_client.error) result
(** [close t] sends one close frame and releases the transport. *)
