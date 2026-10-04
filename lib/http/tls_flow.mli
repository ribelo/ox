(** Cancellation and finalizers: Suspension: may suspend during TLS handshake flow
    reads/writes, Eio.Mutex locking and Eio.Fiber.yield when a writer is busy; depends on
    delegated Cstruct buffers, Eio flow I/O, Ox_http_tls_openssl native TLS and Stdlib
    string/byte operations. Cancellation: propagates Eio.Cancel.Cancelled from handshake
    and flow operations except protected feed and close cleanup; depends on delegated Eio
    flow/provider checks, Ox_http_tls_openssl native TLS, Cstruct buffers and Stdlib
    string/byte operations. Finalizers: create registers no hook and retains the supplied
    raw flow; the owning switch or caller must close it. Locking: separate read, write and
    SSL Eio mutexes serialize the TLS state. Cancellation safety: unsafe because progress
    is lost if a TLS record or handshake is interrupted; the connection state is not
    rewindable. ^nlintd-z5p5 ^nlintd-vneh *)

val failure_message : exn -> string option
(** Return the diagnostic for a TLS failure, or [None] for any other defect. *)

module Testing : sig
  val failure : string -> exn
  (** Construct a TLS failure for transport fault injection. *)
end

type ty = [ Eio.Flow.two_way_ty | Eio.Resource.close_ty ]

val create : raw:ty Eio.Resource.t -> ssl:Ox_http_tls_openssl.ssl -> ty Eio.Resource.t
(** Complete the TLS handshake and wrap the socket. Reads raise [End_of_file] on
    close_notify or TCP EOF at a complete-record boundary, but a truncated or corrupted
    record is a defect (nhttp-7pp8).

    One fiber may read while other fibers write. In-flight ciphertext uses disjoint
    buffers, writers are serialized so records stay intact, and a send does not take a
    lock held across a parked raw read (wsduplex-j4rn). OpenSSL calls are serialized with
    each other and are not overlapped with socket I/O.

    [Eio.Flow.close] sends close_notify, then closes [raw] without waiting for the peer's
    reply. It is idempotent and closes [raw] even if sending fails or is cancelled
    (nhttp-rs5p). The caller still owns [raw]'s switch lifetime; use the returned flow's
    close for a graceful close before switch release. [Eio.Flow.shutdown] remains the raw
    socket's half-close operation.

    @raise Tls_failure
      if the OpenSSL handshake fails; the exception is private and failure_message
      extracts its message. ^nlintd-raises *)
