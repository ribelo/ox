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
val guarded_assertion : string -> (int, string) result -> unit
val guarded_recovery : string -> (unit -> unit) -> (int, string) result -> unit
val guard_success_only : string -> (int -> unit) -> (int, string) result -> unit
val guarded_logging : string -> (int, string) result -> unit
type result_alias = (int, string) result
type disposal_record = { result : result_alias; number : int }
val tuple_wildcard : unit -> int
val record_wildcard : unit -> int
val unused_wildcard_alias : unit -> unit
val retained_wildcard_alias : unit -> result_alias
val retained_tuple_alias : unit -> result_alias * int
val own_tuple_wildcard : unit -> int
val guarded_direct_logging : string -> (int, string) result -> unit
val direct_logging : (int, string) result -> unit
val retained_inner_alias : unit -> result_alias
val retained_outer_alias : unit -> result_alias
val retained_multi_inner : unit -> result_alias
val retained_multi_middle : unit -> result_alias
val retained_multi_outer : unit -> result_alias
val unused_inner_alias : unit -> unit
val unused_multi_alias : unit -> unit
val shadowed_inner_alias : unit -> (int, 'a) result
val shadowed_outer_alias : unit -> (int, 'a) result
val discarded_inner_alias : unit -> unit
val nested_tuple_alias : unit -> int
val retained_inner_tuple : unit -> result_alias * int
val retained_multi_tuple : unit -> result_alias * int
val nested_record_alias : unit -> int
val own_unused_alias : unit -> unit
