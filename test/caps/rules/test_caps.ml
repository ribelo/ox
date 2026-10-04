(* ^ncapslint-w2tq ^ncapslint-8jcy ^ncapslint-snhg: each tier independently. *)
open Ocaml_common

let sites make source =
  let found = ref [] in
  make (fun loc -> found := loc.Location.loc_start.Lexing.pos_lnum :: !found) source;
  List.sort_uniq Int.compare !found

let source_sites (rule : Rules.t) source =
  sites
    (fun emit source ->
      Option.iter
        (fun make -> Syntax.walk source (fun context base -> make emit context base))
        rule.source)
    source

let typed_sites (rule : Rules.t) source =
  sites
    (fun emit source ->
      let dir = Filename.dirname source in
      let unit_name =
        String.capitalize_ascii (Filename.remove_extension (Filename.basename source))
      in
      let annotation =
        Printf.sprintf "%s/.caps_%s.objs/byte/caps_%s__%s.cmt" dir dir dir unit_name
      in
      let artifact = Artifact.read annotation in
      Artifact.check ~source artifact;
      Artifact.setup artifact;
      Option.iter
        (fun make ->
          let iterator : Tast_iterator.iterator = make emit in
          match artifact.info.cmt_annots with
          | Implementation tree -> iterator.structure iterator tree
          | _ -> failwith "implementation required")
        rule.typed)
    source

let rule name = List.hd (Rules.select [ "ox-caps-" ^ name ])

let () =
  let names =
    List.map (fun (op : Caps.operation) -> op.name) Caps.operations @ [ "signature" ]
  in
  List.iter
    (fun name ->
      let rule = rule name in
      let file = String.map (function '-' -> '_' | c -> c) name ^ ".ml" in
      let clean, violating = ("clean/" ^ file, "violating/" ^ file) in
      assert (source_sites rule clean = []);
      if name <> "signature" then assert (source_sites rule violating <> []);
      assert (typed_sites rule clean = []);
      if typed_sites rule violating = [] then failwith ("typed false negative: " ^ name))
    names;
  assert (typed_sites (rule "signature") "violating/signature.ml" = [ 3; 5; 9 ]);
  List.iter
    (fun (name, expected) ->
      let actual = source_sites (rule name) "source_identity.ml" in
      if actual <> expected then failwith (name ^ ": source binder regression"))
    [ ("stdin", [ 5 ]); ("fork", [ 9; 10; 15 ]); ("stdout", [ 19 ]); ("exit", []) ];
  List.iter
    (fun (file, name) ->
      if source_sites (rule name) ("holes/" ^ file) = [] then
        failwith ("unprotected OxCaml parser hole: " ^ file))
    [
      ("schedule.mli", "mint");
      ("sqlite.ml", "fork");
      ("types.ml", "env");
      ("ox_sql_dsl.ml", "forge");
      ("server.ml", "network");
      ("ws_client.ml", "stdout");
    ];
  assert (
    Rules.self_check ~root:"../../.."
      (Rules.select (List.map (fun n -> "ox-caps-" ^ n) names))
    = []);
  assert (Caps_policy.self_check "../../.." = []);
  List.iter
    (fun (pattern, path, want) -> assert (Caps_policy.excluded [ pattern ] path = want))
    [
      ("lib/a", "lib/a/b.ml", true);
      ("lib/a", "lib/ab.ml", false);
      ("lib/a", "./lib/a/b.ml", true);
      ("lib/a", Filename.concat (Sys.getcwd ()) "lib/a/b.ml", true);
      ("lib/a", "lib/a/../../outside.ml", false);
      ("**/generated?.ml", "lib/x/generated1.ml", true);
      ("lib/[ab].ml", "lib/a.ml", true);
      ("lib/[!ab].ml", "lib/c.ml", true);
      ("lib/[!ab].ml", "lib/a.ml", false);
    ];
  print_endline
    "17 source/typed origins, typed signature, lexical binders and allowance evidence: \
     pass"
