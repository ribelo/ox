val allowances : (string * string) list
(** Capability gate policy. ^ncapslint-x3gi ^ncapslint-snhg *)

val self_check : string -> string list

val policy_path : string -> string
(** Normalize lexical path components relative to the invocation root for policy checks.
*)

val excluded : string list -> string -> bool
val check_dune : string list -> (string -> int -> unit) -> unit
