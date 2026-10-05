(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
(** Cancellation and finalizers: Suspension: never suspends in Eio; effects of Stdlib
    operations depend on Ox_caps.Cap_stdlib and Stdlib and are not checked. Cancellation:
    not a cancellation point; delegated Ox_caps.Cap_stdlib and Stdlib calls add no Eio
    check. Finalizers: none. Locking: delegated to Stdlib. *)

val forward : Eio.Switch.t -> unit
val dormant : Eio.Switch.t -> unit
val caught : Eio.Switch.t -> unit

val raises : Eio.Switch.t -> unit
(** @raise Invalid_argument always. *)

val protected : Eio.Switch.t -> unit
(** Suspension: may suspend while yielding. Cancellation: protected throughout.
    Cancellation safety: safe to re-run; the protected yield commits no application state.
    Finalizers: none. Locking: none. *)

val hook : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates Eio.Cancel.Cancelled; delegated Ox_caps.Cap_stdlib and Stdlib
    calls retain their own behaviour. Cancellation safety: safe to re-run; the acquired
    output channel is closed if cancellation reaches the switch check. Finalizers:
    resource closed by the switch hook. Raises Eio.Cancel.Cancelled and Invalid_argument
    from the switch; Eio.Switch.Release_error wraps a failing release callback; other
    exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val bracket : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Finalizers: resource
    closed by a guaranteed finally callback. Fun.Finally_raised wraps a failing close.
    Raises Eio.Cancel.Cancelled and Invalid_argument from the switch; other exceptions
    depend on Ox_caps.Cap_stdlib and Stdlib. *)

val masked_check : Eio.Switch.t -> unit
(** Cancellation: not a cancellation point while protected. Raises Invalid_argument from a
    finished switch. *)

val protected_raise : Eio.Switch.t -> unit
(** Cancellation: protected throughout.
    @raise Failure explicitly even while protected. *)

val match_caught : Eio.Switch.t -> unit

val release_raises : Eio.Switch.t -> unit
(** @raise Invalid_argument when the switch has finished and the callback returns.
    @raise Eio.Switch.Release_error
      when the finished switch invokes the throwing callback. *)

val finalizer_raises : Eio.Switch.t -> unit
(** @raise Fun.Finally_raised when the finalizer fails. *)

(* ^nlintd-truth: known primitive identities and disclosed readiness are not opaque. *)

val primitives : Eio.Switch.t -> int -> int
val thread_spawn : _ Eio.Time.clock -> unit
val domain_spawn : _ Eio.Time.clock -> unit
val named_thread_spawn : _ Eio.Time.clock -> unit

val background : _ Eio.Time.clock -> unit
(** Suspension: may suspend while sleeping. Cancellation: propagates Eio.Cancel.Cancelled.
    Cancellation safety: safe to re-run. Finalizers: none. Locking: none. *)

val buffered_publish : unit Eio.Stream.t -> unit
(** Suspension: never suspends because Eio.Stream.add uses a free slot guaranteed by the
    caller. Cancellation: not a cancellation point when Eio.Stream.add has that free slot;
    Eio.Cancel.Cancelled cannot be delivered without waiting. Cancellation safety: safe to
    re-run; the free-slot branch has no cancellation point and commits once. Finalizers:
    none. Locking: delegated to the stream. *)

(* ^nlintd-truth *)

val visible_operator : Eio.Switch.t -> unit

val result_operator : Eio.Switch.t -> (unit, string) result
(** Suspension: never suspends. Cancellation: not a cancellation point. *)

val local_callback : Eio.Switch.t -> unit
val ignored_callback : Eio.Switch.t -> unit
val deferred_partial : Eio.Switch.t -> unit
val recursive_partial : Eio.Switch.t -> unit
val recursive_quiet : Eio.Switch.t -> unit

val recursive_active : Eio.Switch.t -> unit
(** Suspension: may suspend while invoking the callback. Cancellation: propagates
    Eio.Cancel.Cancelled. Cancellation safety: safe to re-run; the callback changes no
    application state. Finalizers: none. Locking: none. *)

val optional_default : Eio.Switch.t -> string option
(** Suspension: never suspends. Cancellation: not a cancellation point. *)

val scalar_leaves : Eio.Switch.t -> string -> bool
(** Suspension: never suspends. Cancellation: not a cancellation point. *)

val delegated_input : in_channel -> Eio.Switch.t -> string
(** @raise End_of_file from delegated Stdlib.input_line at end of input. *)

(* ^nlintd-truth ^nlintd-raises *)

val callback_caught : Eio.Switch.t -> unit
val callback_recursive_caught : Eio.Switch.t -> unit

val callback_masked : Eio.Switch.t -> unit
(** Suspension: may suspend while yielding. Cancellation: protected throughout.
    Finalizers: none. Locking: none. *)

val callback_wrapped : Eio.Switch.t -> unit
(** @raise Fun.Finally_raised when the callback fails. *)

val stored_only : Eio.Switch.t -> unit

val fiber_daemon : Eio.Switch.t -> unit
(** @raise Invalid_argument when startup checks a finished or wrong-domain switch. *)

val fiber_named : Eio.Switch.t -> unit
(** @raise Invalid_argument when startup checks a finished or wrong-domain switch. *)

val fiber_promise : Eio.Switch.t -> unit
(** @raise Invalid_argument when startup checks a finished or wrong-domain switch. *)
