(* ^safe-1bc7 ^safe-s6km ^safe-xls8: approved Artifact/typed rule seam. *)
open Ocaml_common

let run ~caps =
  let artifact = Artifact.read ~caps "fixtures/.disposal_fixtures.objs/byte/forms.cmt" in
  Artifact.check ~caps ~source:"fixtures/forms.ml" artifact;
  Artifact.setup ~caps artifact;
  let rule = List.hd (Rules.select ~caps [ "ox-discarded-result" ]) in
  let sites = ref [] in
  let iterator =
    Option.get rule.typed (fun loc -> sites := loc.Location.loc_start.pos_lnum :: !sites)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "expected implementation");
  let actual = List.sort_uniq Int.compare !sites in
  let expected = [ 3; 7; 11; 17; 20; 21; 22; 26; 30; 32; 33; 36; 94; 96; 98; 102 ] in
  if actual <> expected then
    failwith
      (Printf.sprintf "expected [%s], got [%s]"
         (String.concat ";" (List.map string_of_int expected))
         (String.concat ";" (List.map string_of_int actual)))

let () = run ~caps:(Ox_caps_door.powerbox ())

(* ^safe-pufa: byte coincidence is not source-origin evidence. *)
let () =
  let root = "/policy" and source = "/policy/source.ml" in
  let id = "ox-discarded-result" in
  let checker = Policy_exception.create ~root ~source ~known:[ id ] ~enabled:[ id ] in
  let lexbuf =
    Lexing.from_string "(ignore (Ok 1))[@ox.allow \"ox-discarded-result: test origin\"]"
  in
  Location.init lexbuf source;
  let ast = Parse.implementation lexbuf in
  let iterator = Policy_exception.collect checker Ast_iterator.default_iterator in
  iterator.structure iterator ast;
  let location filename ghost =
    let position cnum =
      { Lexing.pos_fname = filename; pos_cnum = cnum; pos_lnum = 1; pos_bol = 0 }
    in
    { Location.loc_start = position 2; loc_end = position 3; loc_ghost = ghost }
  in
  if Policy_exception.allows checker ~id (location "/other/source.ml" false) then
    failwith "foreign origin waived";
  if Policy_exception.allows checker ~id (location source true) then
    failwith "ghost origin waived";
  List.iter
    (fun filename ->
      if not (Policy_exception.allows checker ~id (location filename false)) then
        failwith ("same source rejected: " ^ filename))
    [ source; "source.ml"; "/policy/_build/default/source.ml" ];
  let original = location source false in
  let shifted position =
    {
      position with
      Lexing.pos_cnum = position.Lexing.pos_cnum + 5000;
      pos_bol = position.pos_bol + 5000;
    }
  in
  let mapped =
    {
      original with
      Location.loc_start = shifted original.loc_start;
      loc_end = shifted original.loc_end;
    }
  in
  if not (Policy_exception.allows checker ~id mapped) then
    failwith "line-directive byte shift rejected";
  let compiler = "/compiler/recorded.ml" in
  if Policy_exception.allows checker ~id (location compiler false) then
    failwith "unregistered compiler origin waived";
  Policy_exception.checked_source checker ~filename:compiler;
  if not (Policy_exception.allows checker ~id (location compiler false)) then
    failwith "validated compiler spelling rejected";
  if Policy_exception.allows checker ~id (location compiler true) then
    failwith "registered ghost origin waived"
