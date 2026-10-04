type t
(** One-shot HTTP/1.1 client. Each request closes its socket on success, error, timeout or
    cancellation; cancellation propagates to the enclosing Eio scope. *)

type tls

val tls : ?ca_file:string -> unit -> tls
(** [tls ()] uses the system trust store. [ca_file] adds a PEM trust anchor. *)

val create :
  sw:Eio.Switch.t -> net:_ Eio.Net.t -> clock:_ Eio.Time.clock -> ?tls:tls -> unit -> t
(** Suspension: never suspends; this call only constructs or reads OCaml values and
    captures dependencies without invoking them. Cancellation: not a cancellation point;
    this call performs no Eio cancellation check. Finalizers: this call registers no
    switch hook and leaves captured resources with their existing owner. Locking: this
    call acquires no lock; construction of synchronization objects does not acquire them.
    ^nlintd-a7oq *)

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
  ?deadline:Ox.Duration.t ->
  ?response_idle:Ox.Duration.t ->
  ?max_body_bytes:int ->
  unit ->
  (response, error) result
(** [deadline] limits the whole request; [response_idle] resets on each incoming response
    read. The default body limit is 1 MiB. Redirects are returned unchanged. *)
