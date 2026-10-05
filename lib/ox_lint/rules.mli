(** Cancellation and finalizers: Suspension: never suspends during iterator/registry
    construction and checks; synchronous filesystem/compiler work may block the domain;
    operations delegate to Stdlib, Unix, Ox_caps, Caps, Concurrency and Interface_docs and
    their higher-order callbacks; capability object method dispatch depends on the
    supplied provider; running returned visitors depends on caller code. Cancellation: not
    a cancellation point during iterator/registry construction and checks; operations
    delegate to Stdlib, Unix, Ox_caps, Caps, Concurrency and Interface_docs and their
    higher-order callbacks; capability object method dispatch depends on the supplied
    provider; running returned visitors depends on caller code. Finalizers: no hook is
    registered and returned rule records own no OS handle. Locking: no registry lock is
    acquired; compiler/runtime synchronization is delegated to Ocaml_common and Stdlib.
    ^nlintd-z5p5 ^nlintd-vneh ^nlintd-truth *)

open Ocaml_common

type t = {
  id : string;
  message : string;
  violating : string;
  clean : string;
  documentation : string;
  source :
    ((Location.t -> unit) ->
    Syntax.context ->
    Ast_iterator.iterator ->
    Ast_iterator.iterator)
    option;
  typed : ((Location.t -> unit) -> Tast_iterator.iterator) option;
  evidence :
    (emit:(Location.t -> string -> unit) ->
    undecided:(Location.t -> string -> unit) ->
    Artifact.t ->
    unit)
    option;
}
(** Each rule owns its tier, replacement and evidence. [evidence] runs only after source
    freshness and compiler imports are checked; its [undecided] callback is never a
    waivable finding. Legacy fixed-message visitors remain supported. ^nlint-emql
    ^safe-fr73 ^safe-y047 *)

val all : caps:< Ox_caps.Cap.fs_read ; .. > -> t list

val allowances : (string * string * string) list
(** The path-wide allow-list stays empty; named best-effort discards are ordinary
    bindings. ^safe-s6km *)

val dormant : t -> bool
(** Registered but deliberately inactive; ^nlintcov-r3k8 ^nlint-r01u. *)

val applies : root:string -> source:string -> t -> bool
(** Raw concurrency is dormant on every path. Other rules apply to all implementations or,
    for interface rules, all interfaces; direct decider tests do not apply this policy. *)

val select : caps:< Ox_caps.Cap.fs_read ; .. > -> string list -> t list
(** Unknown ids raise [Invalid_argument]; empty selects all. *)

val self_check : caps:< Ox_caps.Cap.fs_read ; .. > -> root:string -> t list -> string list
(** Missing replacement, fixture or rule page produces a named failure. *)
