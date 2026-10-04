open Ocaml_common
open Ox_caps

let run ~(caps : < Cap.fs_read ; Cap.stdout ; Cap.stderr ; .. >) =
  assert (Rules.allowances = []);
  assert (Caps_policy.allowances = []);
  let names = ref [] in
  Syntax.walk ~caps "syntax_fixture.ml" (fun context base ->
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
      (fun names -> Cap_stdlib.eprintf ~caps "[%s]\n" (String.concat ";" names))
      (List.rev !names);
    failwith "scoped source resolution mismatch"
  end;
  let docs = ref 0 in
  Syntax.walk ~caps "syntax_fixture.mli" (fun _ base ->
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
  let rule = List.hd (Rules.select ~caps [ "ox-discarded-result" ]) in
  assert (Rules.self_check ~caps ~root:"../.." [ rule ] = []);
  let mutations =
    [
      { rule with message = "" };
      { rule with violating = "absent" };
      { rule with clean = "absent" };
      { rule with documentation = "absent" };
    ]
  in
  List.iter
    (fun rule -> assert (Rules.self_check ~caps ~root:"../.." [ rule ] <> []))
    mutations;
  Cap_stdlib.print_endline ~caps
    "syntax scopes, attached docs and all four evidence fields: pass"

let () = run ~caps:(Ox_caps_door.powerbox ())
