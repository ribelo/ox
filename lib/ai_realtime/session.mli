(** Cancellation and finalizers: Suspension: may suspend in delegated Ox_http.Ws_client
    connection, frame I/O and close. Cancellation: propagates Eio.Cancel.Cancelled from
    the delegated WebSocket operation. Finalizers: the supplied switch owns the WebSocket;
    these wrappers add no hook. Locking: delegated to Ox_http.Ws_client. Cancellation
    safety: unsafe because progress is lost if frame delivery or receipt is interrupted;
    already-sent frames are not rolled back. ^nlintd-z5p5 ^nlintd-vneh *)

type t
(** Codex Realtime JSON session. The caller's switch owns its WebSocket; cancellation or
    switch exit closes the socket, and explicit close sends a close frame. Credentials are
    revealed only when constructing the Authorization header. *)

type error = [ Ox_http.Ws_client.error | `Invalid_event of Ox_json.issue ]
type event = { kind : string; raw : Ox_json.t }

val connect :
  sw:Eio.Switch.t ->
  net:_ Eio.Net.t ->
  clock:_ Eio.Time.clock ->
  api_key:Ox_observability.Redact.t ->
  ?headers:(string * string) list ->
  ?ca_file:string ->
  ?protocols:string list ->
  ?establishment_timeout:Ox.Duration.t ->
  string ->
  (t, Ox_http.Ws_client.error) result
(** [connect ... url] opens [url] with the bearer header built from [api_key]. [headers]
    are appended after it, so the caller's own protocol headers travel unchanged and it
    must not add a second Authorization; [protocols] are the WebSocket subprotocols the
    peer must select from, and [ca_file] adds a PEM trust anchor to the system store.
    [establishment_timeout] bounds DNS, TCP, TLS and the upgrade only. *)

val send : t -> Ox_json.t -> (unit, Ox_http.Ws_client.error) result
(** [send t json] writes [json] as one compact text frame. *)

val decode : string -> (event, error) result
(** [decode raw] reads the event type from [raw]; a non-object or a missing [type] is
    [`Invalid_event]. Pure. *)

val receive : t -> (event, error) result
(** [receive t] waits for the next event. A binary frame is [`Invalid_event]; pings are
    answered by the transport. *)

val close : ?code:int -> ?reason:string -> t -> (unit, Ox_http.Ws_client.error) result
(** [close t] sends one close frame and releases the transport. *)
