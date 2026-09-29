exception Tls_failure of string
(** TLS protocol, authentication, or truncated-record failure. *)

type ty = [ Eio.Flow.two_way_ty | Eio.Resource.close_ty ]

val create : raw:ty Eio.Resource.t -> ssl:Ox_http_tls_openssl.ssl -> ty Eio.Resource.t
(** Complete the TLS handshake and wrap the socket. Reads raise [End_of_file] on
    close_notify or TCP EOF at a complete-record boundary, but a truncated or corrupted
    record raises [Tls_failure] (nhttp-7pp8).

    [Eio.Flow.close] sends close_notify, then closes [raw] without waiting for the peer's
    reply. It is idempotent and closes [raw] even if sending fails or is cancelled
    (nhttp-rs5p). The caller still owns [raw]'s switch lifetime; use the returned flow's
    close for a graceful close before switch release. [Eio.Flow.shutdown] remains the raw
    socket's half-close operation. *)
