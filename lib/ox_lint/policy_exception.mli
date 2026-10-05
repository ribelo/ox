type t
(** Checked, expression/binding-local policy decisions, never evidence or authority
    waivers. Only discarded-result and future partial-option/partial-list are eligible. An
    eligible ID must still name an installed rule. ^safe-pufa *)

val create : root:string -> source:string -> known:string list -> enabled:string list -> t

val checked_source : t -> filename:string -> unit
(** Register the exact compiler source spelling only after [Artifact.check] has validated
    that annotation as evidence for the checker source. *)

val collect :
  t -> Ocaml_common.Ast_iterator.iterator -> Ocaml_common.Ast_iterator.iterator

val allows : t -> id:string -> Ocaml_common.Location.t -> bool
(** Returns true only for a finding within the nearest matching decision, recording its
    use. Disabled rules cannot consume a decision. *)

val finish : t -> complete:bool -> (Ocaml_common.Location.t -> string -> unit) -> unit
(** Report malformed/forbidden decisions regardless of rule selection. Report unused
    enabled decisions only after complete evidence; disabled ones are not stale. *)
