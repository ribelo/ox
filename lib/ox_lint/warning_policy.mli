open Ocaml_common

type setting = Warning | Fatal
type directive = setting * string
type decision = Clean | Restriction of string | Unverified of string

val evaluate : directive list -> decision
(** Effective warning settings against the pinned Ox compiler/Dune dev policy. No waiver;
    targeted suppressions already excluded by policy are equivalent. No I/O, suspension,
    cancellation point, finalizer or lock. *)

val evaluate_attached : inherited:directive list -> directive list -> decision
(** Evaluate attached attributes in compiler order (reverse AST attribute list). No I/O,
    suspension, cancellation point, finalizer or lock. *)

val reconcile :
  recorded:string list ->
  flags:string list option ->
  compiler_flags:string list option ->
  decision
(** Compare supported literal Dune fields with the effective recorded compiler settings.
    [Clean] means agreement, not policy safety; [evaluate] checks safety separately. The
    pinned root-language dev [:standard] supplies fatal [+a]; compiler-specific
    [:standard] is empty. The artifact checker selects audited language-dependent
    standards for reconciliation, never to lower the protected root policy. Unresolved
    expansions and content disagreement are [Unverified]. No I/O, suspension, cancellation
    point, finalizer or lock. *)

val check :
  caps:< Ox_caps.Cap.fs_read ; .. > ->
  artifact:Artifact.t ->
  emit:(Location.t -> string -> unit) ->
  undecided:(Location.t -> string -> unit) ->
  unit
(** Inspect the checked artifact's exact arguments, source attributes and ancestor Dune
    compiler policy. Suspension: may suspend in callbacks; synchronous filesystem work can
    block. Cancellation: depends on callbacks; callback behavior in compiler and channel
    helpers is delegated to their upstream implementations; exceptions propagate
    unchanged. Cancellation safety: unsafe because progress is lost; retries repeat
    callback findings. Finalizers: private read channels close on success and exceptions;
    no switch hook. Locking: no lock is acquired by the checker.

    Failure reports inconsistent source/compiler metadata or a delegated callback
    exception. *)
