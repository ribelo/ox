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

val race_deadline :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** A race branch containing a known sleep; ^nlintc-4gjw. *)
