(* ^safe-pcom ^safe-u7cx: pure typed seam over actual checked compiler evidence. *)
open Ocaml_common

let () =
  let caps = (Ox_caps_door.powerbox () :> < Ox_caps.Cap.fs_read >) in
  let source = Sys.argv.(1) and annotation = Sys.argv.(2) in
  let expected_effects = int_of_string Sys.argv.(3)
  and expected_unknown = int_of_string Sys.argv.(4) in
  let effects = ref [] and unknown = ref [] and conditions = ref [] in
  let collect sites loc message =
    if
      message = "" || loc.Location.loc_ghost
      || loc.loc_start.Lexing.pos_cnum >= loc.loc_end.Lexing.pos_cnum
      || Filename.basename loc.loc_start.pos_fname <> Filename.basename source
      || Filename.basename loc.loc_end.pos_fname <> Filename.basename source
      || not
           (List.exists
              (fun condition ->
                condition.Location.loc_start.Lexing.pos_cnum
                <= loc.Location.loc_start.Lexing.pos_cnum
                && loc.Location.loc_end.Lexing.pos_cnum
                   <= condition.Location.loc_end.Lexing.pos_cnum)
              !conditions)
    then failwith "diagnostic must name evidence at the removable assertion condition";
    sites := (loc, message) :: !sites
  in
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let iterator =
    Assertion_effects.check ~caps ~emit:(collect effects) ~undecided:(collect unknown)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree ->
      let base = Tast_iterator.default_iterator in
      let sites =
        {
          base with
          expr =
            (fun self e ->
              (match e.Typedtree.exp_desc with
              | Texp_assert (condition, _) ->
                  conditions := condition.exp_loc :: !conditions
              | _ -> ());
              base.expr self e);
        }
      in
      sites.structure sites tree;
      iterator.structure iterator tree
  | _ -> failwith "expected compiled implementation");
  (* Oracle controls preserve category counts and remain inside assertion spans. *)
  (if Array.length Sys.argv = 7 then
     match (Sys.argv.(6), !effects) with
     | "--duplicate-effect-site", first :: _second :: rest ->
         effects := first :: first :: rest
     | "--wrong-effect-site", (loc, message) :: rest ->
         let start = loc.Location.loc_start in
         let shifted = { start with Lexing.pos_cnum = start.pos_cnum + 1 } in
         effects := ({ loc with Location.loc_start = shifted }, message) :: rest
     | _ -> failwith "invalid oracle control");
  let actual_effects = List.length !effects and actual_unknown = List.length !unknown in
  if (actual_effects, actual_unknown) <> (expected_effects, expected_unknown) then
    failwith
      (Printf.sprintf "%s: expected effects=%d unknown=%d; got effects=%d unknown=%d: %s"
         source expected_effects expected_unknown actual_effects actual_unknown
         (String.concat "; " (List.map snd (!effects @ !unknown))));
  let filename = Filename.basename source in
  let site category (loc, _) =
    let start = loc.Location.loc_start and stop = loc.Location.loc_end in
    Printf.sprintf "%s:%s:%d:%d:%d:%d" filename category start.Lexing.pos_lnum
      (start.pos_cnum - start.pos_bol + 1)
      stop.Lexing.pos_lnum
      (stop.pos_cnum - stop.pos_bol + 1)
  in
  (* Columns are one-based; ends are exclusive. Sorting retains multiplicity.
     Expectations are literal harness-owned data, never derived from this tree. *)
  let expected =
    if Sys.argv.(5) = "-" then []
    else
      String.split_on_char ',' Sys.argv.(5)
      |> List.map (fun coordinates -> filename ^ ":" ^ coordinates)
      |> List.sort String.compare
  in
  let actual =
    List.map (site "effect") !effects @ List.map (site "unknown") !unknown
    |> List.sort String.compare
  in
  if actual <> expected then
    failwith
      (Printf.sprintf "%s: exact diagnostic multiset mismatch: expected [%s]; got [%s]"
         source (String.concat ", " expected) (String.concat ", " actual))
