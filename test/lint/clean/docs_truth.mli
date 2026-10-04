(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
(** Cancellation and finalizers: Suspension: never suspends in Eio; effects of Stdlib
    operations depend on Ox_caps.Cap_stdlib and Stdlib and are not checked. Cancellation:
    not a cancellation point. Finalizers: none. Locking: delegated to Stdlib. *)

val forward : Eio.Switch.t -> unit
val dormant : Eio.Switch.t -> unit
val caught : Eio.Switch.t -> unit

val raises : Eio.Switch.t -> unit
(** @raise Invalid_argument always. *)

val protected : Eio.Switch.t -> unit
(** Suspension: may suspend while yielding. Cancellation: protected throughout.
    Finalizers: none. Locking: none. *)

val hook : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Finalizers: resource
    closed by the switch hook. Raises Eio.Cancel.Cancelled and Invalid_argument from the
    switch; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val bracket : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Finalizers: resource
    closed by a guaranteed finally callback. Raises Eio.Cancel.Cancelled and
    Invalid_argument from the switch; other exceptions depend on Ox_caps.Cap_stdlib and
    Stdlib. *)

val masked_check : Eio.Switch.t -> unit
(** Cancellation: not a cancellation point while protected. Raises Invalid_argument from a
    finished switch. *)

val protected_raise : Eio.Switch.t -> unit
(** Cancellation: protected throughout. @raise Failure explicitly even while protected. *)

val match_caught : Eio.Switch.t -> unit

val release_raises : Eio.Switch.t -> unit
(** @raise Invalid_argument when the switch has finished and the callback returns.
    @raise Eio.Switch.Release_error
      when the finished switch invokes the throwing callback. *)

val finalizer_raises : Eio.Switch.t -> unit
(** @raise Fun.Finally_raised when the finalizer fails. *)
