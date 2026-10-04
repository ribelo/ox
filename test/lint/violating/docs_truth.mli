(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
(** Cancellation and finalizers: Suspension: never suspends; effects of Stdlib operations depend on Ox_caps.Cap_stdlib and Stdlib and are not checked. Cancellation: not a cancellation point. Finalizers: none. Locking: delegated to Stdlib. *)

val forward : Eio.Switch.t -> unit
val no_check : Eio.Switch.t -> unit
val wrong_raise : Eio.Switch.t -> unit
(** @raise Invalid_argument supposedly. *)

val unattested : Eio.Switch.t -> unit
(** @raise Invalid_argument supposedly. *)

val callback : Eio.Switch.t -> (unit -> unit) -> unit
val success_only : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled and Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val late_hook : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled and Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val irrelevant_hook : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled and Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val conditional_hook : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> bool -> unit
(** Cancellation: propagates. Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled and Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val cancellable_finalizer : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Suspension: may suspend in finalizer. Cancellation: propagates. Cancellation safety: safe to re-run. Raises Eio.Cancel.Cancelled and Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)

val partial_catch : Eio.Switch.t -> unit

val locking_only : Eio.Switch.t -> (unit -> unit) -> unit
(** Locking: delegated to the caller callback. *)

val masked_added_check : Eio.Switch.t -> unit
(** Cancellation: not a cancellation point while protected; adds no cancellation check. Raises Invalid_argument from the switch. *)

val protected_cancellation : Eio.Switch.t -> unit
(** Cancellation: protected throughout. Raises Eio.Cancel.Cancelled explicitly. *)

val swallowed_cancel : caps:< Ox_caps.Cap.fs_write ; .. > -> Eio.Switch.t -> string -> unit
(** Cancellation: classified as caught locally. Cancellation safety: safe to re-run. Raises Invalid_argument; other exceptions depend on Ox_caps.Cap_stdlib and Stdlib. *)
