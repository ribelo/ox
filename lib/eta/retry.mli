val retry :
  clock:_ Eio.Time.clock ->
  ('e, 'o) Schedule.t ->
  (unit -> ('a, 'e) result) ->
  ('a, 'e) result
(** Schedule-driven loops; sleeping uses only the supplied clock and is promptly
    cancellable. They create no switch or finalizer. *)

val repeat :
  clock:_ Eio.Time.clock ->
  ('a, 'o) Schedule.t ->
  (unit -> ('a, 'e) result) ->
  ('o, 'e) result
