val direct : int -> string
(** Canonical ownership controls, without warning suppressions. ^nonce-mjpe *)

val aliased : int -> string
val opened : int -> string
val unreviewed_many : (unit -> int) -> unit -> int
val shadowed : int -> int
val shadowed_stdlib : int -> int
