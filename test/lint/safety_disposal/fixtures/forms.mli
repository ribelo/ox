val unused : unit -> unit
val shadowed : unit -> unit
val erased : (int, string) result -> unit
val logged : (int, string) result -> unit
val option : (int, string) result -> int option
val iterator : (int, string) result -> unit
val direct : unit -> unit
val aliases : unit -> unit
val constant_alias : (int, string) result -> unit
val piped : (int, string) result -> unit
val applied : (int, string) result -> unit
val destructured : unit -> int
val recover : (int, string) result -> int
val mapped : (int, string) result -> (int, [> `Named of string ]) result

module Own : sig
  type ('a, 'e) result = Error of 'e | Ok of 'a
end

val homonym : (int, string) Own.result -> unit
val propagated : unit -> (int, string) result
val used : unit -> int
val classified : (int, string) result -> bool
val status : (int, string) result -> int
val observed : (int, string) result -> (int, string) result
val discriminated : (int, [ `Empty | `Timeout ]) result -> int option
val close_recovery : (unit -> unit) -> (int, string) result -> unit
val computed_health : (int, string) result -> bool
val expected_error : (int, string) result -> unit
val unexpected_error : (int, string) result -> unit
val expected_error_stdlib : (int, string) result -> unit
val checked_payload : string -> (int, string) result -> unit
val shadowed_terminal : (int, string) result -> unit
val unchecked_payload : (int, string) result -> unit
val unrelated_guard : string -> string -> (int, string) result -> unit
val shadowed_comparison : string -> (int, string) result -> unit
val expected_error_predef : (int, string) result -> unit
val expected_error_invalid_arg : (int, string) result -> unit
val expected_error_raise : (int, string) result -> unit
val expected_error_raise_notrace : (int, string) result -> unit
