(** Concurrent combinators as thin wrappers over Eio's [Fiber.pair]/[both]/[all]/[any] and
    [Fiber.List.map]. None owns a switch: they run in the caller's cancellation context,
    so cancelling the caller cancels every branch, and Eio cancels and awaits the losers
    before the combinator returns. [sw] is the caller's switch and is only checked
    ([Invalid_argument] if finished, the cancellation if cancelled) before anything
    starts.

    One law governs all of them: a combinator raises exactly what a body raises, returns
    exactly the [result] a body returns, adds nothing and swallows nothing; the
    interruption of losers is suppressed onto the primary outcome (Eio drops it, so
    [Scope.run] sees the primary failure alone). The first typed [Error] or exception ends
    the computation; the remaining branches are cancelled and awaited, their finalizers
    run, and a branch not yet started never starts. *)

val par :
  sw:Eio.Switch.t ->
  (unit -> ('a, 'e) result) ->
  (unit -> ('b, 'e) result) ->
  ('a * 'b, 'e) result
(** Both branches run concurrently and both results are returned; the first [Error] ends
    the pair with that [Error]. *)

val both :
  sw:Eio.Switch.t ->
  (unit -> (unit, 'e) result) ->
  (unit -> (unit, 'e) result) ->
  (unit, 'e) result
(** {!par} for branches with no value. *)

val all : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list -> ('a list, 'e) result
(** All branches run concurrently; values are returned in input order. The first [Error]
    ends the computation with that [Error]. [all ~sw []] is [Ok []]. *)

val for_each :
  sw:Eio.Switch.t ->
  concurrency:int ->
  'a list ->
  ('a -> ('b, 'e) result) ->
  ('b list, 'e) result
(** {!all} over [f x] for each [x], with at most [concurrency] fibers running at once
    ([Fiber.List.map ~max_fibers]); results keep input order.
    @raise Invalid_argument if [concurrency < 1]. *)

val race : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list -> ('a, 'e Cause.t) result
(** The first [Ok] wins and the other branches are cancelled and awaited. A branch that
    returns [Error] does not end the race; if every branch does, the result is
    [Error (Cause.Concurrent causes)] with the [Cause.Fail]s in input order, and a single
    branch's failure is returned unwrapped. [race ~sw []] is
    [Error (Cause.Concurrent [])]. An exception in any branch ends the race at once and is
    raised unchanged. *)

val race_first : sw:Eio.Switch.t -> (unit -> ('a, 'e) result) list -> ('a, 'e) result
(** The first branch to return, [Ok] or [Error], is the result; the others are cancelled
    and awaited. An exception in any branch is raised unchanged.
    @raise Invalid_argument on an empty list. *)

val with_background :
  sw:Eio.Switch.t ->
  (unit -> (unit, 'e) result) ->
  (unit -> ('a, 'e) result) ->
  ('a, 'e) result
(** [supervised_error] with the background as a daemon {!Scope.fork_error_daemon} and the
    body in the scope body. The body's [Ok] ends the background (cancelled and awaited)
    and is the result; the background's [Error] or exception cancels the body and wins;
    the body's own [Error] or exception wins the same way. A background that returns
    [Ok ()] leaves the body running. The body runs in the calling fiber. *)
