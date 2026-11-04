(** Result syntax has no cancellation or finalizer effects. *)
module Syntax : sig
  val ( let* ) : ('a, 'e) result -> ('a -> ('b, 'e) result) -> ('b, 'e) result
  val ( let+ ) : ('a, 'e) result -> ('a -> 'b) -> ('b, 'e) result
end

val bind : ('a, 'e) result -> ('a -> ('b, 'e) result) @ local once yielding -> ('b, 'e) result
(** [bind r f] is [f x] for [Ok x], else [r]'s error. [f] may be [local] and
    [yielding], so a local scope handle or a suspension token can be used after
    it; write it with [let%bind] from [ppx_ox_let] (^nlet-q79e). *)

val map : ('a, 'e) result -> ('a -> 'b) @ local once yielding -> ('b, 'e) result
(** [map r f] is [Ok (f x)] for [Ok x], else [r]'s error; [let%map]. *)

val both : ('a, 'e) result -> ('b, 'e) result -> ('a * 'b, 'e) result
(** [both a b] pairs two results, the first error winning; [let%bind ... and ...]. *)
