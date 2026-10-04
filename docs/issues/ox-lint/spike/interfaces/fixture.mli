(* Fresh control for written versus effective modes. *)
type t = { value : int }
val take_local : t @ local -> int
(** Takes a local parameter. Does not suspend, observe cancellation or register finalizers. *)
val take_global : t @ global -> int
val take_default : t -> int
val take_unique : t @ unique -> int
val take_portable : (unit -> unit) @ portable -> unit
val portable_value : unit -> unit @@ portable
