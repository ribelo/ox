open Ocaml_common

(* ^safe-9gfb ^safe-4zis: the declaration is the policy target, not its uses or type. *)
let source emit _context (base : Ast_iterator.iterator) =
  {
    base with
    value_description =
      (fun self declaration ->
        if List.mem "%identity" declaration.Parsetree.pval_prim then
          emit declaration.pval_loc;
        base.value_description self declaration);
  }
