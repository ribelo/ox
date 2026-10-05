(* ^nonce-4jzx ^nonce-lrzq: affine callback boundaries. *)
(** Ox's resource helpers ([useInScope], [useCloseableInScope]) over an Eio switch. A
    resource is released by [Eio.Switch.on_release], so the rules are Eio's: releases run
    in reverse registration order after every fiber of the switch has finished, with
    cancellation protected, whether the switch ended by success, failure or cancellation.
    A release that raises makes the switch fail with that exception (a finalizer failure to
    {!Scope.run}). Acquiring is not protected: an [acquire] that is cancelled or raises
    registers nothing, and the caller's exception propagates. There is no [bracket]: pair
    a switch with these two functions. ^nfloor-elwp

    Cancellation and finalizers: Suspension: may suspend in the caller's callbacks;
    callers must supply a non-suspending release, which this helper does not enforce.
    Close behaviour depends on the Eio resource provider.
    Cancellation: depends on acquire; Eio protects both normal switch release and
    immediate release on a finished switch. Finalizers: after acquisition returns, Eio
    owns release and runs it exactly once, at switch exit or immediately if the switch
    has finished; a normally returning immediate release is followed by
    [Invalid_argument], and Ox does not retry release.
    Locking: Eio locks registration, but no lock is held around callbacks. ^nfloor-once
    Cancellation safety: unsafe because progress is lost; an interrupted acquire can
    have effects before returning a resource and is responsible for its own cleanup.
    ^nlintd-a7oq ^nlintd-4ja0

    @raise Invalid_argument if [sw] is finished when the release is registered, after
      Eio has run release exactly once under cancellation protection and it has
      returned normally. *)

val use_in_scope : sw:Eio.Switch.t -> (unit -> 'a) @ local once -> ('a -> unit) @ once -> 'a
(** [use_in_scope ~sw acquire release] runs [acquire] in the calling fiber, registers
    [release] on [sw] and returns the resource. Other exceptions depend on [acquire]
    and [release] callbacks and propagate; acquisition defects register no cleanup.
    @raise Eio.Switch.Release_error if immediate release on a finished switch raises;
      Eio wraps the release exception. *)

val use_closeable_in_scope :
  sw:Eio.Switch.t ->
  (unit -> ([> Eio.Resource.close_ty ] as 'a) Eio.Resource.t) @ local once ->
  'a Eio.Resource.t
(** {!use_in_scope} for an Eio resource that can be closed (a flow, a socket, a file, a
    process): the release is [Eio.Resource.close]. Other exceptions depend on the
    [acquire] callback and the Eio close provider; acquisition defects register no cleanup.
    @raise Eio.Switch.Release_error if immediate close on a finished switch raises;
      Eio wraps the close exception. *)
