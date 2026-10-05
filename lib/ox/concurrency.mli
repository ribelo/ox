(** A validated positive concurrency bound. All operations are pure and synchronous.
    ^nparse-gb03 ^safe-6ukl *)

type t [@@immediate]
(** An integer greater than or equal to one, distinct from the other bounded domains. *)

val of_int : int -> (t, [> `Invalid ]) result
(** [of_int value] returns [Error `Invalid] exactly when [value < 1]. *)

val to_int : t -> int
(** [to_int value] is the validated integer. *)
