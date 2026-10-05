open Ocaml_common

val source :
  (Location.t -> unit) -> Syntax.context -> Ast_iterator.iterator -> Ast_iterator.iterator
(** Policy check for source declarations using [%identity], regardless of their claimed
    type. No trust or naming exemption. Construction does not suspend or register cleanup;
    traversal delegates suspension, cancellation and locking to the supplied iterator and
    emitter, whose exceptions propagate. ^safe-9gfb ^safe-4zis ^safe-01za *)
