(* ^ncapslint-w2tq ^ncapslint-8jcy ^ncapslint-snhg: each tier independently. *)
open Ocaml_common

let sites make source =
  let found = ref [] in
  make (fun loc -> found := loc.Location.loc_start.Lexing.pos_lnum :: !found) source;
  List.sort_uniq Int.compare !found

let source_sites ~caps (rule : Rules.t) source =
  sites
    (fun emit source ->
      Option.iter
        (fun make ->
          Syntax.walk ~caps source (fun context base -> make emit context base))
        rule.source)
    source

let typed_sites ~caps (rule : Rules.t) source =
  sites
    (fun emit source ->
      let dir = Filename.dirname source in
      let unit_name =
        String.capitalize_ascii (Filename.remove_extension (Filename.basename source))
      in
      let annotation =
        Printf.sprintf "%s/.caps_%s.objs/byte/caps_%s__%s.cmt" dir dir dir unit_name
      in
      let artifact = Artifact.read ~caps annotation in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact;
      Option.iter
        (fun make ->
          let iterator : Tast_iterator.iterator = make emit in
          match artifact.info.cmt_annots with
          | Implementation tree -> iterator.structure iterator tree
          | _ -> failwith "implementation required")
        rule.typed)
    source

let rule ~caps name = List.hd (Rules.select ~caps [ "ox-caps-" ^ name ])

let () =
  let caps = Ox_caps_door.powerbox () in
  let names =
    List.map (fun (op : Caps.operation) -> op.name) Caps.operations @ [ "signature" ]
  in
  List.iter
    (fun name ->
      let rule = rule ~caps name in
      let file = String.map (function '-' -> '_' | c -> c) name ^ ".ml" in
      let clean, violating = ("clean/" ^ file, "violating/" ^ file) in
      assert (source_sites ~caps rule clean = []);
      if name <> "signature" then assert (source_sites ~caps rule violating <> []);
      assert (typed_sites ~caps rule clean = []);
      if name <> "mint" && name <> "forge" then
        assert (typed_sites ~caps rule "clean/signature.ml" = []);
      if typed_sites ~caps rule violating = [] then
        failwith ("typed false negative: " ^ name))
    names;
  assert (
    typed_sites ~caps (rule ~caps "signature") "violating/signature.ml" = [ 3; 5; 9 ]);
  List.iter
    (fun (name, expected) ->
      let actual = source_sites ~caps (rule ~caps name) "source_identity.ml" in
      if actual <> expected then failwith (name ^ ": source binder regression"))
    [ ("stdin", [ 5 ]); ("fork", [ 9; 10; 15 ]); ("stdout", [ 19 ]); ("exit", []) ];
  List.iter
    (fun (file, name) ->
      if source_sites ~caps (rule ~caps name) ("holes/" ^ file) = [] then
        failwith ("unprotected OxCaml parser hole: " ^ file))
    [
      ("schedule.mli", "mint");
      ("sqlite.ml", "fork");
      ("types.ml", "env");
      ("ox_sql_dsl.ml", "forge");
    ];
  let launcher =
    Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps "../../../scripts/caps-gate"
      In_channel.input_all
  in
  let commands =
    String.split_on_char '\n' launcher
    |> List.filter (fun line -> not (String.starts_with ~prefix:"#" (String.trim line)))
  in
  assert (
    not
      (List.exists
         (fun line ->
           let n = String.length line in
           let rec contains i =
             i + 7 <= n && (String.sub line i 7 = "--allow" || contains (i + 1))
           in
           contains 0)
         commands));
  List.iter
    (fun (path, expected) -> assert (Caps_policy.declares_door ~caps path = expected))
    [
      ("boundaries/mixed/allowed.ml", true);
      ("boundaries/mixed/denied.ml", false);
      ("boundaries/comments/value.ml", false);
      ("boundaries/direct/entry.ml", true);
      ("boundaries/direct/sub/entry.ml", false);
      ("boundaries/included/sub/entry.ml", true);
    ];
  let public = List.hd (Rules.select ~caps [ "ox-public-exception" ]) in
  assert (source_sites ~caps public "boundaries/private/holder.mli" = []);
  assert (source_sites ~caps public "boundaries/private/public.mli" = [ 2 ]);
  assert (Caps_policy.allowances = []);
  assert (Rules.allowances = []);
  assert (
    Rules.self_check ~caps ~root:"../../.."
      (Rules.select ~caps (List.map (fun n -> "ox-caps-" ^ n) names))
    = []);
  assert (Caps_policy.self_check ~caps "../../.." = []);
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
  Ox_caps.Cap_stdlib.print_endline ~caps
    "17 source/typed origins, typed signature, lexical binders and allowance evidence: \
     pass"
