(* Copyright (c) 2026 Ox contributors. SPDX-License-Identifier: MIT *)

(** Low-level OpenSSL 3.x binding. No I/O — pure state-machine driver. *)

type ctx
(** Opaque SSL_CTX wrapper. *)

type ssl
(** Opaque SSL wrapper with memory BIO pair. *)

type session
(** Opaque TLS session reference for explicit client-side resumption. *)

type server_certificate
(** Certificate entry selected by SNI on server handshakes. *)

val create_ctx : unit -> ctx
(** Create a client SSL_CTX with Ox's TLS 1.2/1.3 policy, default system trust store, and
    peer verification enabled. *)

val ctx_load_ca : ctx -> string -> unit
(** [ctx_load_ca ctx path] adds [path] (a PEM CA file) to the trust store of [ctx]. The
    default system trust store remains in eff. Raises [Failure] if the file cannot be
    loaded. *)

val create_server_ctx :
  ?certificates:server_certificate list ->
  ?require_sni_match:bool ->
  certificate_chain_file:string ->
  private_key_file:string ->
  alpn_protocols:string list ->
  unit ->
  ctx
(** Create a server SSL_CTX with Ox's TLS policy, certificate chain, private key, ALPN
    selection callback, and OpenSSL session cache enabled for TLS resumption. Raises
    [Failure] when the certificate or private key cannot be loaded or do not match. *)

val server_certificate :
  server_name:string ->
  certificate_chain_file:string ->
  private_key_file:string ->
  server_certificate
(** Build a certificate entry for [create_server_ctx ~certificates]. *)

val create_server_ssl : ctx -> ssl
(** Create a server SSL connection with memory BIOs in accept state. *)

val create_ssl :
  ctx -> hostname:string option -> ip:string option -> alpn_protocols:string list -> ssl
(** Create an SSL connection with memory BIOs. [hostname] sets SNI and, when [ip] is
    absent, DNS peer certificate identity verification. [ip] sets IP peer certificate
    identity verification. [alpn_protocols] are sent in wire order. *)

type ssl_error = { code : int; detail : string option }
(** [code] is the [SSL_get_error] value. [detail] is this operation's OpenSSL diagnostic
    captured immediately after [SSL_get_error], or [None] when the queue had no string.
    WANT_READ and ZERO_RETURN do not capture queue text. WANT_WRITE is skipped the same
    way in the native capture filter, but this memory-BIO public surface does not expose a
    legitimate WANT_WRITE outcome. *)

type handshake_result = Handshake_ok | Handshake_error of ssl_error
type io_result = Io_bytes of int | Io_error of ssl_error

val handshake : ssl -> handshake_result
(** Drive one step of the TLS handshake. Returns [Handshake_ok] on completion, or
    [Handshake_error] with the raw [SSL_get_error] code and any owned diagnostic from that
    call. *)

val read : ssl -> Cstruct.buffer -> int -> int -> io_result
(** [read ssl buf off len] attempts to read up to [len] decrypted bytes into [buf] at
    offset [off].
    @raise Invalid_argument
      if the slice is outside [buf] or [len] is not representable as a native [size_t]. *)

val write : ssl -> Cstruct.buffer -> int -> int -> io_result
(** [write ssl buf off len] attempts to write [len] decrypted bytes from [buf] at offset
    [off].
    @raise Invalid_argument
      if the slice is outside [buf] or [len] is not representable as a native [size_t]. *)

val shutdown : ssl -> int
(** Initiate SSL shutdown. Returns [SSL_shutdown] result. *)

val bio_read : ssl -> Cstruct.buffer -> int -> int -> int
(** Read encrypted bytes from OpenSSL's write BIO (data to send over the wire).
    @raise Invalid_argument if the slice is outside [buf] or [len] exceeds [INT_MAX]. *)

val bio_write : ssl -> Cstruct.buffer -> int -> int -> int
(** Write encrypted bytes into OpenSSL's read BIO (data received from the wire).
    @raise Invalid_argument if the slice is outside [buf] or [len] exceeds [INT_MAX]. *)

val bio_write_pending : ssl -> int
(** Number of encrypted bytes pending in the write BIO. *)

val ssl_pending : ssl -> int
(** Number of decrypted bytes readable from SSL without touching the network. *)

val get_alpn_selected : ssl -> string option
(** The ALPN protocol selected by the server, if any. *)

val get_version : ssl -> string
(** The negotiated TLS protocol version, such as ["TLSv1.3"]. *)

val get_servername : ssl -> string option
(** The client SNI server name observed by a server SSL, if any. *)

val get_verify_result : ssl -> int
(** [X509_V_OK] (0) on success, or an [X509_V_ERR_*] code. *)

val get_session : ssl -> session option
(** Return a retained TLS session after a completed handshake, when OpenSSL made one
    available. *)

val set_session : ssl -> session -> unit
(** Attach a previous client session before driving the next client handshake. Raises
    [Failure] if OpenSSL rejects the session. *)

val session_reused : ssl -> bool
(** [true] when the completed handshake reused a previously supplied session. *)

val err_peek_error : unit -> string option
(** Peek at the top OpenSSL error string, if any. *)

val err_clear_error : unit -> unit
(** Clear the OpenSSL error stack. *)

val random_bytes : int -> bytes
(** [random_bytes len] returns [len] bytes from OpenSSL [RAND_bytes]. Raises
    [Invalid_argument] if [len] is negative or exceeds the native [RAND_bytes] [int]
    range, before allocating. Raises [Failure] if OpenSSL cannot provide random bytes. *)

val sha1 : string -> string
(** [sha1 input] returns the 20-byte SHA-1 digest from OpenSSL EVP. Ox uses this for
    protocol-mandated WebSocket accept keys, not as a security primitive exposed to
    applications. *)
