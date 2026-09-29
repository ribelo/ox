(** Go/Ox-style [select] over {!Channel}s: block until one clause can complete and return
    that clause's result; the channels of the other clauses are left untouched.

    Which clause fired is what the clauses' handlers return: give each the variant it
    should map to. A clause on a closed channel is ready: it completes with the typed
    closure [Error `Done] / [Error (`Error e)], never an exception, so the shutdown of one
    channel is ordinary control flow (the caller drops it from the next select).

    [select] registers no finalizer. It runs in the calling fiber and owns no switch or
    fiber of its own beyond the short-lived waiters of a blocking wait, which are
    cancelled and awaited before it returns. Cancelling the caller cancels the wait and
    propagates as Eio's cancellation; no clause has fired, so no element is sent or taken.
    A handler that raises has its exception propagate unchanged, after its clause has
    fired (the element is gone). Like {!Channel}, single domain.

    Fairness: clauses on channels are probed round-robin — each call starts one clause
    further along than the last (a process-wide cursor), so two channels that are always
    ready are served alternately instead of the first starving the second. The default and
    timeout clauses are not part of the rotation. *)

type 'r clause
(** A clause whose firing produces a value of type ['r]. *)

val receive_clause :
  ('a, 'e) Channel.t -> (('a, 'e Channel.closed) result -> 'r) -> 'r clause
(** Ready when the channel has an element (the handler gets [Ok v], the element taken) or
    is closed for receiving (the handler gets the closure). *)

val send_clause :
  ('a, 'e) Channel.t -> 'a -> ((unit, 'e Channel.closed) result -> 'r) -> 'r clause
(** Ready when the channel has room (the value is sent, the handler gets [Ok ()]) or is
    closed for sending (the value is not sent, the handler gets the closure). *)

val default_clause : (unit -> 'r) -> 'r clause
(** Fires at once when no channel clause is ready, without waiting. At most one per
    {!select}. *)

val timeout_clause : clock:_ Eio.Time.clock -> Duration.t -> (unit -> 'r) -> 'r clause
(** Fires when no channel clause has become ready [Duration.t] after the {!select} began,
    measured on [clock]; a ready channel clause always wins over an expired timeout. At
    most one per {!select}. *)

val select : 'r clause list -> 'r
(** [select clauses] blocks until a clause fires and returns its handler's result. A
    {!default_clause} makes it non-blocking. With neither a channel clause nor a default
    or timeout clause it would wait for ever and raises instead.
    @raise Invalid_argument
      on an empty list, or on more than one default or more than one timeout clause. *)

val receive : ('a, 'e) Channel.t list -> ('a, 'e Channel.closed) result
(** [receive channels] is {!select} over a {!receive_clause} on each channel with the
    handler [Fun.id]: the first element available from any of them, or the closure of one
    that is closed. Ox's [select(sourceA, sourceB)].
    @raise Invalid_argument on an empty list. *)
