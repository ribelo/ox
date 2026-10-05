(** Scripted loopback POST peer for ^safe-o2b6 ^safe-3o27 regression tests. *)

type action =
  | Before_commit
  | Lose_reply
  | Withhold_reply
  | Truncate_reply
  | Reply of int

type t = {
  endpoint : string;
  requests : int ref;
  effects : int ref;
  committed : unit Eio.Promise.t;
  closed : unit Eio.Promise.t;
}
(** [committed] resolves after the first complete POST takes effect; [closed] resolves
    after a withheld response observes the client close its socket. *)

val start : sw:Eio.Switch.t -> net:_ Eio.Net.t -> action list -> t
(** Listen on ephemeral loopback and serve the scripted outcomes. An exhausted script
    commits and loses the reply. Every accepted connection carries one POST.

    Suspension: may suspend through Eio.Net.listen; the daemon later waits in
    Eio.Net.accept_fork and its request handler, not in the caller; formatting is
    delegated to Stdlib.Printf.sprintf. Cancellation: propagates Eio.Cancel.Cancelled from
    Eio.Net.listen; child cancellation and failures belong to the supplied switch, and
    startup delegates switch validation to Eio.Fiber.fork_daemon and formatting to
    Stdlib.Printf.sprintf. Finalizers: Eio.Net.listen registers its listener with [sw];
    the daemon belongs to that switch and Eio.Net.accept_fork closes each accepted socket
    after its handler. Locking: this helper acquires no lock; Eio.Net and Eio.Fiber own
    their synchronization. Cancellation safety: unsafe because progress is lost;
    restarting on the same switch can add another listener rather than recover a partially
    started peer.

    Raises Invalid_argument for invalid switch startup through Eio.Fiber.fork_daemon;
    other exceptions depend on Eio.Net.listen, Eio.Net.listening_addr and
    Stdlib.Printf.sprintf.

    @raise Assert_failure if the loopback listener reports a non-TCP address. *)
