@@ portable

(** Result of a finished scope. Inspection is pure: no cancellation or finalizers run
    here. *)
type ('a, 'e) t = Success of 'a | Failure of 'e Cause.t

val pp :
  (Format.formatter -> 'a -> unit) ->
  (Format.formatter -> 'e -> unit) ->
  Format.formatter ->
  ('a, 'e) t ->
  unit

val is_interrupt_only : ('a, 'e) t -> bool

val to_result : ('a, 'e) t -> (('a, 'e) result, 'e Cause.t) result
(** [Ok (Error e)] is possible only for a bare [Fail e]; other failures are [Error cause].
*)

val process_code : ('a, 'e) t -> int
