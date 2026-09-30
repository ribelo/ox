type t
(** Direct-style RFC 6455 client over Ox's TCP and verified OpenSSL TLS. *)

type message = [ `Text of string | `Binary of bytes ]

type error =
  [ `Url of string
  | `Connect of string
  | `Tls of string
  | `Timeout
  | `Upgrade_failed of int * (string * string) list
  | `Protocol of string
  | `Message_too_large
  | `Closed of int * string ]

val connect :
  sw:Eio.Switch.t ->
  net:_ Eio.Net.t ->
  clock:_ Eio.Time.clock ->
  ?ca_file:string ->
  ?headers:(string * string) list ->
  ?protocols:string list ->
  ?establishment_timeout:Ox.Duration.t ->
  ?max_message_bytes:int ->
  string ->
  (t, error) result
(** The switch owns the socket. The timeout bounds DNS, TCP, TLS and upgrade only;
    cancellation propagates to the caller. Headers cannot override upgrade fields. *)

val selected_protocol : t -> string option
val send_text : t -> string -> (unit, error) result
val send_binary : t -> bytes -> (unit, error) result

val receive : t -> (message, error) result
(** Receives the next complete message; automatically answers pings and skips pongs.
    Keepalives have no lifetime limit. A connection-wide control-frame bucket allows a
    burst of 32 frames and replenishes 32 frames per second using [connect]'s clock. One
    receiver and concurrent senders are supported within one Eio domain. A terminal
    transport failure is retained before shutdown: subsequent receives and sends return
    that cause, even while shutdown is suspended. Cancellation propagates without being
    recorded as a transport failure. *)

val close : ?code:int -> ?reason:string -> t -> (unit, error) result
(** Sends one close control frame and releases the transport. *)
