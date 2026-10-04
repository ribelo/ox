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

type body = [ `Read of bytes | `Skipped ]
(** Successfully acquired bytes, including genuinely empty bodies, or explicit skip. *)

type response = { status : int; headers : (string * string) list; body : body }

type body_reason =
  [ `Truncated
  | `Malformed of string
  | `Too_large
  | `Idle_timeout
  | `Timeout
  | `Tls of string
  | `Closed
  | `Connect of string ]

type body_failure = {
  status : int;
  headers : (string * string) list;
  reason : body_reason;
}
(** The final response head, preserving header order and duplicates, and a nonrecursive
    acquisition failure. No partial payload escapes. *)

type error =
  [ `Connect of string
  | `Tls of string
  | `Timeout
  | `Idle_timeout
  | `Protocol of string
  | `Body of body_failure
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
  ?on_head:(status:int -> headers:(string * string) list -> [ `Read | `Skip ]) ->
  unit ->
  (response, error) result
(** [deadline] covers connect, TLS handshake, write, heads, policy and body acquisition.
    Before the final head it returns [`Timeout]; after it, [`Body] with [`Timeout].
    [response_idle] resets on each incoming response read. The default payload bound is 1
    MiB; exceeding it returns [`Body] with [`Too_large]. Redirects are not followed.
    [on_head] runs exactly once for the final head, never for informational heads; its
    default is [`Read] for every status. [`Skip] returns [`Skipped] and closes without
    acquiring the body. HEAD, 204 and 304 read as [`Read Bytes.empty]. Informational heads
    are consumed until a final response; 101 is an unsupported [`Protocol]. Each head is
    limited to 32 KiB and 256 fields. Informational heads also share a cumulative 32 KiB
    wire-byte budget including status lines and CRLF. The trailer block has a separate
    cumulative 32 KiB wire-byte budget including its final CRLF; exceeding it is [`Body]
    with [`Malformed]. Every framing line is at most 32 KiB.

    Suspension: may suspend during DNS, connect, TLS, write, response reads and [on_head].
    Cancellation: propagates external Eio cancellation and callback exceptions unchanged
    with their backtraces; only the explicitly requested deadlines become typed failures.
    Cancellation safety: unsafe because progress is lost and the peer may already have
    processed the request; retrying can duplicate its effects. Finalizers: the
    request-owned switch closes the socket on read, skip, failure, deadline, cancellation
    or a raising policy before the request exits. Locking: no client lock spans [on_head];
    TLS locks cover only transport operations. *)
