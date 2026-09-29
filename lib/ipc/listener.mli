(** nlimit-ylvw: a private, one-line Unix socket listener. Pathname ownership assumes a
    private namespace without hostile mutation by another process of the same UID; OCaml's
    Unix.open_flag has no O_NOFOLLOW. Same-user processes are trusted: ownership and
    identity checks protect against stale state, accidental changes and other users, not
    against a hostile same-user process. *)

type policy = {
  peers : int;
  backlog : int;
  max_line_bytes : int;
  max_reply_bytes : int;
  ingress : Ox.Duration.t;
  egress : Ox.Duration.t;
}

val default_policy : policy
(** Sixteen active peers, backlog sixteen, 64 KiB lines/replies, and one second each for
    ingress and egress. Pure; no cancellation/finalizers. *)

type error =
  [ `Invalid_policy of string
  | `Unsafe_runtime_dir
  | `Inaccessible_runtime_dir
  | `Ownership_conflict of string
  | `Active_listener
  | `Lock_conflict
  | `Lock_identity
  | `Probe_failed
  | `Bind_failed of string ]

type ('decode, 'handler) peer_error =
  [ `Ingress_timeout
  | `Ingress_too_large
  | `Ingress_closed
  | `Decode of 'decode
  | `Handler of 'handler
  | `Handler_budget_exceeded
  | `Egress_timeout
  | `Egress_too_large
  | `Egress_closed
  | `Disconnected ]

val run :
  sw:Eio.Switch.t ->
  fs:_ Eio.Path.t ->
  net:_ Eio.Net.ty Eio.Resource.t ->
  clock:_ Eio.Time.clock ->
  path:string ->
  ?policy:policy ->
  decode:(string -> ('request, 'decode) result) ->
  encode:('response -> string) ->
  budget:('request -> Ox.Duration.t option) ->
  handler:('request -> ('response, 'handler) result) ->
  ?on_budget_exceeded:('request -> Ox.Duration.t -> 'response) ->
  ?error_response:(('decode, 'handler) peer_error -> 'response option) ->
  ?on_peer_error:(('decode, 'handler) peer_error -> unit) ->
  unit ->
  (unit, error) result
(** Acquire against [sw], start bounded admission, and return immediately. Native Unix
    calls implement pathname identity and binding. Each peer receives one request and at
    most one newline-terminated response. A peer disconnect interrupts its handler. On
    switch exit daemon fibers are cancelled and joined before the socket is
    identity-checked and removed; the persistent lockfile is never removed.
    Callback/finalizer defects propagate through Eio's switch. Typed peer errors are
    reported through [on_peer_error] if supplied, not raised as listener failures.

    When [on_budget_exceeded] is supplied, a handler cancelled at its budget answers that
    peer with the response the callback derives from the decoded request and the elapsed
    budget: it is encoded and written through the same egress path as a handler's own
    reply — byte bound, then egress deadline — and the connection closes as after any
    reply. [on_peer_error] still reports `Handler_budget_exceeded. Without the callback
    the request is answered with nothing, as before. The callback runs in that peer's
    fiber with no listener-imposed deadline of its own, so it must be quick.

    When [error_response] is supplied, an ingress-side failure — a decode failure, an
    over-large request line, or an ingress deadline — is answered with the response the
    callback derives from that peer error, encoded and written through the same egress
    path as a handler's own reply: byte bound, then egress deadline, then close. It is
    consulted at most once per peer and never for `Ingress_closed or `Disconnected: a peer
    that went away gets nothing. A reply the byte bound or egress deadline refuses is
    reported through [on_peer_error] without replacing the ingress cause that prompted it.
    Handler failures and egress failures are not ingress failures: [on_budget_exceeded]
    owns a budget cut, and no reply is attempted after a write has already failed. The
    callback runs in that peer's fiber, so it must be quick. *)
