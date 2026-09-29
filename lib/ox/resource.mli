(** Ox's resource helpers ([useInScope], [useCloseableInScope]) over an Eio switch. A
    resource is released by [Eio.Switch.on_release], so the rules are Eio's: releases run
    in reverse registration order after every fiber of the switch has finished, with
    cancellation protected, whether the switch ended by success, failure or cancellation.
    A release that raises makes the switch fail with that exception (a finalizer failure to
    {!Scope.run}). Acquiring is not protected: an [acquire] that is cancelled or raises
    registers nothing, and the caller's exception propagates. There is no [bracket]: pair
    a switch with these two functions. ^nfloor-elwp *)

val use_in_scope : sw:Eio.Switch.t -> (unit -> 'a) @ local -> ('a -> unit) -> 'a
(** [use_in_scope ~sw acquire release] runs [acquire] in the calling fiber, registers
    [release] on [sw] and returns the resource. *)

val use_closeable_in_scope :
  sw:Eio.Switch.t ->
  (unit -> ([> Eio.Resource.close_ty ] as 'a) Eio.Resource.t) @ local ->
  'a Eio.Resource.t
(** {!use_in_scope} for an Eio resource that can be closed (a flow, a socket, a file, a
    process): the release is [Eio.Resource.close]. *)
