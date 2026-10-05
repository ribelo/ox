(** Cancellation and finalizers: Suspension: never suspends during iterator/registry
    construction and checks; synchronous filesystem/compiler work may block the domain;
    operations delegate to Stdlib, Ox_caps, Env, Envaux, Longident and Path and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; running returned visitors depends on caller code. Cancellation: not a
    cancellation point during iterator/registry construction and checks; operations
    delegate to Stdlib, Ox_caps, Env, Envaux, Longident and Path and their higher-order
    callbacks; capability object method dispatch depends on the supplied provider; running
    returned visitors depends on caller code. Finalizers: no hook is registered; iterator
    state is an in-memory value. Locking: compiler and Stdlib synchronization are
    delegated; each iterator owns mutable traversal state and must not be shared across
    simultaneous walks. ^nlintd-z5p5 ^nlintd-vneh ^nlintd-truth *)

open Ocaml_common

val catch_all :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Cancellation-origin and bare wildcard/exn handlers; ^nlintc-du4v. *)

val suspending_finalizer :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Unprotected, path-resolved suspension in a finalizer; ^nlintc-g6k3. *)

val stdlib_lock :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Known scheduler suspension while a Stdlib mutex or semaphore remains held.
    Construction and synchronous critical sections are legal. ^nlintc-kdcl *)

val raw_concurrency :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Deciders independent of the rule table's application policy; ^nlintc-j03j. *)

val obj_magic :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** All values named magic* originating in Stdlib.Obj; ^nlintc-7be1. *)

val obj_magic_artifact :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  artifact:Artifact.t ->
  undecided:(Location.t -> string -> unit) ->
  (Location.t -> unit) ->
  Tast_iterator.iterator
(** Admit only the exact physical cast in the verified global atomic guard. Any
    candidate's missing or contradictory native/source/peer evidence is undecided;
    ordinary casts remain findings. No local callback conversion.

    Suspension: never suspends in Eio itself; synchronous compiler/filesystem work may
    block the domain; operations delegate to Stdlib, Ox_caps, Env, Envaux, Longident,
    Path, Cmi_format, Cmt_format, Compilation_unit, Ctype, Import_info, Load_path, Shape,
    Types, Unix and their higher-order callbacks; capability object method dispatch and
    returned visitor calls depend on the provider and caller-provided [emit] and
    [undecided]. Cancellation: not a cancellation point in Eio itself; operations delegate
    to Stdlib, Ox_caps, Env, Envaux, Longident, Path, Cmi_format, Cmt_format,
    Compilation_unit, Ctype, Import_info, Load_path, Shape, Types, Unix and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; returned visitor calls depend on caller code. Raises: [Failure] on
    unavailable or contradictory imported compiler evidence; filesystem and compiler-libs
    failures and caller callback exceptions propagate. Finalizers: none are registered.
    Locking: compiler/Stdlib synchronization is delegated; initialize and traverse only
    with the matching compiler environment; the visitor must not be shared across
    simultaneous walks. ^nonce-ldtz ^nonce-mjpe *)

val race_deadline :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** A race branch containing a known sleep; ^nlintc-4gjw. *)
