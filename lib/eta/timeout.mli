val timeout :
  clock:_ Eio.Time.clock ->
  Duration.t ->
  (unit -> ('a, ([> `Timeout ] as 'e)) result) ->
  ('a, 'e) result
(** Deadline measured only by the supplied clock. Timeout cancels and awaits the body
    before returning; body finalizers run before return. An external cancellation
    propagates and is classified by [Scope.run]. *)
