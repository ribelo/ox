type t
module Source : sig
  type t
  val cancel : t -> unit
end
val with_ : (t @ local -> 'a) @ local once -> 'a
val source : t @ local -> Source.t
val is_canceled : t @ local -> bool
(* Scratch-only composition helper: reborrow a global source inside each Eio fiber. *)
val with_source : Source.t -> (t @ local -> 'a) @ local once -> 'a
val attach : t @ local -> Eio.Condition.t -> unit
val detach : t @ local -> Eio.Condition.t -> unit
