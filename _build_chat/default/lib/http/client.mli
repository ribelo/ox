type t
(** One-shot HTTP/1.1 client. Each request closes its socket on success, error, timeout or
    cancellation; cancellation propagates to the enclosing Eio scope. *)

type tls

val tls : ?ca_file:string -> unit -> tls
(** [tls ()] uses the system trust store. [ca_file] adds a PEM trust anchor. *)

val create :
  sw:Eio.Switch.t -> net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> ?tls:tls -> unit -> t

type response = { status : int; headers : (string * string) list; body : bytes }

type error =
  [ `Connect of string
  | `Tls of string
  | `Timeout
  | `Idle_timeout
  | `Protocol of string
  | `Body_too_large
  | `Closed ]

val request :
  t ->
  method_:string ->
  url:string ->
  ?headers:(string * string) list ->
  ?body:bytes ->
  ?deadline:Eta.Duration.t ->
  ?response_idle:Eta.Duration.t ->
  ?max_body_bytes:int ->
  unit ->
  (response, error) result
(** [deadline] limits the whole request; [response_idle] resets on each incoming response
    read. The default body limit is 1 MiB. Redirects are returned unchanged. *)
