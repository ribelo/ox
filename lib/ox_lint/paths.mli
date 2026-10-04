open Ocaml_common
open Ox_caps

(** Cancellation and finalizers: Suspension: never suspends in Eio itself; synchronous
    filesystem/compiler work may block the domain; operations delegate to Stdlib, Ox_caps,
    Env, Envaux, Longident and Path and their higher-order callbacks; capability object
    method dispatch depends on the supplied provider; running returned visitors depends on
    caller code. Cancellation: not a cancellation point in Eio itself; operations delegate
    to Stdlib, Ox_caps, Env, Envaux, Longident and Path and their higher-order callbacks;
    capability object method dispatch depends on the supplied provider; running returned
    visitors depends on caller code. Finalizers: none are registered. Locking: compiler
    caches retain their existing locking. ^nlintd-z5p5 ^nlintd-vneh ^nlintd-truth *)

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
