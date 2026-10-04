open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio; compiler environment
    reconstruction and normalization may read interfaces synchronously. Cancellation: not
    a cancellation point. Finalizers: none are registered. Locking: compiler caches retain
    their existing locking. *)

val env : caps:< Cap.fs_read ; .. > -> Env.t -> Env.t
(** Reconstruct an annotation's environment; missing dependencies fail closed. *)

val lid : string list -> Longident.t
val value : caps:< Cap.fs_read ; .. > -> string list -> Path.t option

val module_ : caps:< Cap.fs_read ; .. > -> string list -> Path.t option
(** Canonical initial-environment identities, never lexical spelling; ^nlintc-j03j. *)

val is_value : caps:< Cap.fs_read ; .. > -> Path.t list -> Typedtree.expression -> bool
val in_module : caps:< Cap.fs_read ; .. > -> Path.t list -> Typedtree.expression -> bool
val values : caps:< Cap.fs_read ; .. > -> string list list -> Path.t list
val modules : caps:< Cap.fs_read ; .. > -> string list list -> Path.t list
