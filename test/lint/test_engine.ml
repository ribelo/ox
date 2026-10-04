open Ocaml_common

let () =
  let names = ref [] in
  Syntax.walk "syntax_fixture.ml" (fun context base ->
      {
        base with
        expr =
          (fun self e ->
            (match e.Parsetree.pexp_desc with
            | Pexp_ident id -> names := Syntax.resolve context id.txt :: !names
            | _ -> ());
            base.expr self e);
      });
  let expected =
    [
      [ "Eio.Fiber.fork"; "Stdlib.fork"; "fork" ];
      [ "Local.fork" ];
      [ "Eio.Fiber.fork" ];
      [ "Local.fork"; "Eio.Fiber.fork"; "Stdlib.fork"; "fork" ];
      [ "Eio.Fiber.fork"; "Stdlib.fork"; "fork" ];
      [ "Eio.Fiber.fork" ];
    ]
  in
  if List.rev !names <> expected then begin
    List.iter
      (fun names -> Printf.eprintf "[%s]\n" (String.concat ";" names))
      (List.rev !names);
    failwith "scoped source resolution mismatch"
  end;
  let docs = ref 0 in
  Syntax.walk "syntax_fixture.mli" (fun _ base ->
      {
        base with
        value_description =
          (fun self value ->
            List.iter
              (fun attr -> if attr.Parsetree.attr_name.txt = "ocaml.doc" then incr docs)
              value.pval_attributes;
            base.value_description self value);
      });
  assert (!docs = 1);
  let rule = List.hd Rules.all in
  assert (Rules.self_check ~root:"../.." [ rule ] = []);
  let mutations =
    [
      { rule with message = "" };
      { rule with violating = "absent" };
      { rule with clean = "absent" };
      { rule with documentation = "absent" };
    ]
  in
  List.iter (fun rule -> assert (Rules.self_check ~root:"../.." [ rule ] <> [])) mutations;
  print_endline "syntax scopes, attached docs and all four evidence fields: pass"
