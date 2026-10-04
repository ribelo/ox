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
