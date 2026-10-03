@@ portable

(** Millisecond-precision durations copied from v1. Pure operations do not suspend,
    observe cancellation, or register finalizers. *)

type t : value mod portable contended

val zero : t
val ms : int -> t
val seconds : int -> t
val minutes : int -> t
val hours : int -> t
val days : int -> t
val weeks : int -> t
val to_ms : t -> int
val to_seconds : t -> float
(** Length in seconds, the unit of Eio's clocks ([Eio.Time.sleep], [Eio.Time.now]). Exact
    for whole milliseconds. *)

val of_seconds : float -> t
(** [of_seconds s] is [s] seconds rounded to the nearest millisecond; a negative [s]
    is {!zero}, as {!ms} clamps.
    @raise Invalid_argument if [s] is NaN or too large to represent. *)

val to_seconds_float : t -> float
(** Alias of {!to_seconds}, kept for existing callers. *)
val is_zero : t -> bool
val add : t -> t -> t
val ( + ) : t -> t -> t
val subtract : t -> t -> t
val times : t -> int -> t
val divide : t -> int -> t option
val min : t -> t -> t
val max : t -> t -> t

val clamp : min:t -> max:t -> t -> t
(** [clamp ~min ~max t] is [t] restricted to [[min, max]]. Equal bounds are valid. Does
    not swap reversed bounds.
    @raise Invalid_argument if [min] exceeds [max]. *)

val between : min:t -> max:t -> t -> bool
val compare : t -> t -> int
val scale : t -> float -> t

val humanize : t -> string
(** Render a compact human-readable duration such as ["1s 250ms"] or ["2d 3h 4m"]. Zero
    renders as ["0"]. *)

val pp : Format.formatter -> t -> unit
val equal : t -> t -> bool
