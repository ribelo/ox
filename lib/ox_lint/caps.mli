(** Cancellation and finalizers: Suspension: never suspends during iterator/registry
    construction and checks; synchronous filesystem/compiler work may block the domain;
    operations delegate to Stdlib and Ocaml_common and their higher-order callbacks;
    capability object method dispatch depends on the supplied provider; running returned
    visitors depends on caller code. Cancellation: not a cancellation point during
    iterator/registry construction and checks; operations delegate to Stdlib and
    Ocaml_common and their higher-order callbacks; capability object method dispatch
    depends on the supplied provider; running returned visitors depends on caller code.
    Finalizers: no hook is registered and compiler/path caches remain process-owned.
    Locking: compiler and Stdlib synchronization are delegated; iterators carry mutable
    traversal state and must not be shared across simultaneous walks. ^nlintd-z5p5
    ^nlintd-vneh ^nlintd-truth *)

open Ocaml_common
(** Compiler-resolved capability rules. ^ncapslint-nf4t ^ncapslint-8jcy *)

type operation = { name : string; calls : string list list }

val operations : operation list

val source :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  string ->
  (Location.t -> unit) ->
  Syntax.context ->
  Ast_iterator.iterator ->
  Ast_iterator.iterator

val raw :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  string ->
  (Location.t -> unit) ->
  Tast_iterator.iterator

val signature :
  caps:< Ox_caps.Cap.fs_read ; .. > -> (Location.t -> unit) -> Tast_iterator.iterator
(** Follow real capability tokens from function parameters through aliases, tuple
    components, constructor/variant payloads and record fields. Global and locally minted
    tokens are not parameter authority. Shared payload nodes are visited once per
    substituted state rather than unfolded as a tree. ^ncapslint-8jcy *)
