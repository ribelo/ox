open Ocaml_common

val env : Env.t -> Env.t
(** Reconstruct an annotation's environment; missing dependencies fail closed. *)

val lid : string list -> Longident.t
val value : string list -> Path.t option

val module_ : string list -> Path.t option
(** Canonical initial-environment identities, never lexical spelling; ^nlintc-j03j. *)

val is_value : Path.t list -> Typedtree.expression -> bool
val in_module : Path.t list -> Typedtree.expression -> bool
val values : string list list -> Path.t list
val modules : string list list -> Path.t list
