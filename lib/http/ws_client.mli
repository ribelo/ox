(** Cancellation and finalizers: Suspension: may suspend in delegated Eio networking, TLS
    handshake, frame I/O and Eio mutex acquisition; depends on delegated Cstruct buffers,
    Ox_http.Tls_flow, Unix random initialization, Stdlib frame/string/collection
    operations and Eio provider I/O; delegated callback dispatch and
    Ox_http.Ox_http_tls_openssl, Stdlib operations retain their own behaviour.
    Cancellation: propagates Eio.Cancel.Cancelled from those operations; depends on
    delegated Eio provider checks, Ox_http.Tls_flow, Unix random initialization, Cstruct
    buffers and Stdlib frame/string/collection operations; delegated callback dispatch and
    Ox_http.Ox_http_tls_openssl, Stdlib operations retain their own behaviour. Finalizers:
    the supplied switch owns the connection and failed connection attempts close their
    acquired flow. Locking: an Eio mutex serializes outbound frames and close state.
    Cancellation safety: unsafe because progress is lost if frame delivery or receipt is
    interrupted; already-sent bytes are not rolled back. ^nlintd-z5p5 ^nlintd-vneh *)

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
(** The switch owns the socket. [establishment_timeout] defaults to ten seconds and bounds
    DNS, TCP, TLS and HTTP upgrade together, never the established stream (^oxpie-g2x6).
    Expiry returns [`Timeout] and releases any pending socket; cancellation propagates to
    the caller and also releases it. Headers cannot override upgrade fields.

    @raise Invalid_argument
      if max_message_bytes is negative or sw is finished. ^nlintd-raises

    @raise Tls_failure
      if the delegated OpenSSL TLS handshake fails; the exception is private to Tls_flow
      and failure_message extracts its message. ^nlintd-truth *)

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
