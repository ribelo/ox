val timeout :
  clock:_ Eio.Time.clock ->
  Duration.t ->
  (unit -> ('a, ([> `Timeout ] as 'e)) result) ->
  ('a, 'e) result
(** [Eio.Time.with_timeout] taking a {!Duration.t}: an alias, not a second implementation.
    The deadline is measured only by the supplied clock. Timeout cancels and awaits the
    body before returning; body finalizers run before return. An external cancellation
    propagates and is classified by [Scope.run].

    Suspension: may suspend in the caller callback and Eio.Time.with_timeout while
    awaiting its cancellation. Cancellation: propagates Eio.Cancel.Cancelled external
    cancellation; deadline cancellation returns [Error `Timeout]. Finalizers: Eio awaits
    the timed body before returning; resource cleanup remains the callback's
    responsibility. Locking: no lock is held around the callback. Cancellation safety:
    unsafe because progress is lost; body effects before cancellation are not rolled back.
    ^nlintd-a7oq *)

val timeout_mono :
  clock:_ Eio.Time.Mono.t ->
  Duration.t ->
  (unit -> ('a, ([> `Timeout ] as 'e)) result) ->
  ('a, 'e) result
(** [timeout_mono ~clock duration f] runs [f] with an elapsed-time deadline on [clock],
    independent of wall-clock corrections. It delegates to [Eio.Time.Timeout.seconds] and
    [Eio.Time.Timeout.run], using the same [Eio.Fiber.first] cancellation machinery as
    {!timeout}. A callback result ([Ok] or [Error]) is returned unchanged if it settles
    before the deadline; expiry cancels and awaits the callback and returns
    [Error `Timeout]. Exceptions from the callback or its cleanup retain Eio's propagation
    and combination semantics.

    Suspension: may suspend in the caller callback and Eio.Time.Timeout.run while awaiting
    completion or cancellation. Cancellation: propagates Eio.Cancel.Cancelled from
    external interruption of Eio waits or the caller callback; deadline cancellation
    returns [Error `Timeout]. Finalizers: no switch is created or closed by this wrapper;
    Eio awaits the callback, including cleanup of switches it opens, while resources
    attached to an enclosing switch remain owned by that switch. Locking: no lock is held
    around the callback. Cancellation safety: unsafe because progress is lost; callback
    effects before cancellation are not rolled back and restarting repeats them.
    ^nmono-8jcy *)
