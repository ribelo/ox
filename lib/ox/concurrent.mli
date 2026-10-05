(* ^nonce-nngp: affine callback boundaries. *)
(** Concurrent combinators as thin wrappers over Eio's [Fiber.pair]/[both]/[all]/[any] and
    [Fiber.List.map]. None owns a switch: they run in the caller's cancellation context,
    so cancelling the caller cancels every branch, and Eio cancels and awaits the losers
    before the combinator returns. [sw] is the caller's switch and is only checked
    ([Invalid_argument] if finished, the cancellation if cancelled) before anything
    starts.

    [par], [both], [all] and [for_each] end on the first typed [Error] or exception; the
    remaining branches are cancelled and awaited. [race] waits for a success or all typed
    failures, whereas [race_first] uses the first completed outcome. Loser cancellation is
    suppressed; other simultaneous defects can be combined by Eio. Callback effects that
    completed before cancellation remain. ^nlintd-truth

    Cancellation and finalizers: Suspension: may suspend in Eio fiber joins and caller
    callbacks; delegated callback dispatch and Eio, Stdlib, Stdlib.List, Stdlib.Printexc
    operations retain their own behaviour. Cancellation: propagates Eio.Cancel.Cancelled
    from the initial switch check (which raises Invalid_argument if finished), branch
    waits and caller callbacks; delegated callback dispatch and Eio, Stdlib, Stdlib.List,
    Stdlib.Printexc operations retain their own behaviour. Finalizers: Eio awaits
    cancelled branches before returning; callback cleanup remains the callback's
    responsibility. Locking: this wrapper holds no lock around caller callbacks.
    Cancellation safety: unsafe because progress is lost; completed branch effects are not
    rolled back and restarting repeats them. ^nlintd-a7oq ^nlintd-4ja0

    @raise Invalid_argument if [sw] is finished. *)

val par :
  sw:Eio.Switch.t ->
  (unit -> ('a, 'e) result) @ once ->
  (unit -> ('b, 'e) result) @ once ->
  ('a * 'b, 'e) result
(** Both branches run concurrently and both results are returned; the first [Error] ends
    the pair with that [Error]. *)

val both :
  sw:Eio.Switch.t ->
  (unit -> (unit, 'e) result) @ once ->
  (unit -> (unit, 'e) result) @ once ->
  (unit, 'e) result
(** {!par} for branches with no value. *)

val all : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list @ once -> ('a list, 'e) result
(** All branches run concurrently; values are returned in input order. The first [Error]
    ends the computation with that [Error]. [all ~sw []] is [Ok []]. *)

val for_each :
  sw:Eio.Switch.t ->
  concurrency:int ->
  'a list ->
  ('a -> ('b, 'e) result) ->
  ('b list, 'e) result
(** {!all} over [f x] for each [x], with at most [concurrency] fibers running at once
    ([Fiber.List.map ~max_fibers]); results keep input order. The mapper remains
    many-use: it is called once per item, not once per invocation of [for_each].
    @raise Invalid_argument if [concurrency < 1]. *)

val race : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list @ once -> ('a, 'e Cause.t) result
(** The first [Ok] wins and the other branches are cancelled and awaited. A branch that
    returns [Error] does not end the race; if every branch does, the result is
    [Error (Cause.Concurrent causes)] with the [Cause.Fail]s in input order, and a single
    branch's failure is returned unwrapped. [race ~sw []] is
    [Error (Cause.Concurrent [])]. An exception in any branch ends the race at once and is
    raised unchanged. *)

val race_first : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list @ once -> ('a, 'e) result
(** The first branch to return, [Ok] or [Error], is the result; the others are cancelled
    and awaited. An exception in any branch is raised unchanged.
    @raise Invalid_argument on an empty list. *)

val with_background :
  sw:Eio.Switch.t ->
  (unit -> (unit, 'e) result) @ once ->
  (unit -> ('a, 'e) result) @ once ->
  ('a, 'e) result
(** [supervised_error] with the background as a daemon {!Scope.fork_error_daemon} and the
    body in the scope body. The body's [Ok] ends the background (cancelled and awaited)
    and is the result; the background's [Error] or exception cancels the body and wins;
    the body's own [Error] or exception wins the same way. A background that returns
    [Ok ()] leaves the body running. The body runs in the calling fiber. *)
