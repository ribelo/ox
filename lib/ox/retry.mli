type ('a, 'e) policy = {
  is_success : 'a -> bool;
  is_worth_retrying : 'e -> bool;
  on_retry : int -> ('a, 'e) result -> unit;
}
(** Ox's [ResultPolicy] and [onRetry]. [is_success] says whether an [Ok] value ends the
    retrying (a reply that parsed but says "try later" is retried when it returns [false]);
    [is_worth_retrying] says whether an [Error] may be retried (a hopeless error fails
    fast when it returns [false]); [on_retry attempt result] runs before each sleep, with
    the 1-based number of the attempt that just failed and its result. *)

val default_policy : ('a, 'e) policy
(** Every [Ok] is a success, every [Error] is worth retrying, [on_retry] does nothing: the
    behaviour of {!retry} without a policy. *)

val retry :
  clock:_ Eio.Time.clock ->
  ?policy:('a, 'e) policy ->
  (('a, 'e) result, 'o) Schedule.t ->
  (unit -> ('a, 'e) result) @ local ->
  ('a, 'e) result
(** Run the thunk until it settles: a success ([Ok] with [is_success]) or a hopeless
    [Error] returns at once; any other attempt asks the schedule (its input is the
    attempt's [result]) whether to continue, sleeps the schedule's delay on [clock] and
    runs again. When the schedule ends the last attempt's result is returned unchanged,
    [Ok] included. Jittered schedules capture their required random source when
    constructed. Sleeping is promptly cancellable; no switch or finalizer is created. *)

val repeat :
  clock:_ Eio.Time.clock ->
  ('a, 'o) Schedule.t ->
  (unit -> ('a, 'e) result) @ local ->
  ('o, 'e) result
(** Run the thunk, feeding each [Ok] to the schedule, until it ends; an [Error] returns at
    once. Sleeping uses only the supplied clock and is promptly cancellable. *)
