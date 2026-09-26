@@ portable

type t : value mod portable
(** Identity of an Eta-owned interruption. Pure operations have no cancellation or
    finalizer effects; IDs are allocated only when a combinator stops work. *)

val create : unit -> t
val equal : t -> t -> bool
val compare : t -> t -> int
val pp : Format.formatter -> t -> unit
val to_string : t -> string

val stop : t -> exn
(** Private interruption marker; callers cannot construct one themselves. *)

val of_exn : exn -> t option
