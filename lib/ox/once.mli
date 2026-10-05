(** The affine-to-Eio boundary. A guarded callback may be dropped; this is not a
    must-run or must-close guarantee. ^nonce-ldtz *)

val guard : (unit -> 'a) @ once -> (unit -> 'a) @ many
(** [guard f] returns a many-use function that enters [f] at most once. The flag
    is claimed atomically before calling [f], and remains claimed if [f] raises
    or is cancelled. A second invocation raises [Invalid_argument].
    Construction never suspends or checks cancellation; invocation delegates
    suspension and cancellation to [f]. No finalizer or lock is held around [f].
    ^nonce-ldtz *)
