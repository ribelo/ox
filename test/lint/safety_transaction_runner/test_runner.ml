(* ^safe-ldtb ^safe-j6t8 ^safe-y047 ^safe-tlyw: fresh, physical, duplicate-preserving evidence. *)
open Ocaml_common

let () =
  let caps = (Ox_caps_door.powerbox () :> < Ox_caps.Cap.fs_read >) in
  let source = Sys.argv.(1) and annotation = Sys.argv.(2) in
  let expected_defects = int_of_string Sys.argv.(3)
  and expected_unknown = int_of_string Sys.argv.(4) in
  let defects = ref [] and unknown = ref [] in
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let compiled_filename =
    match artifact.info.cmt_sourcefile with
    | Some filename -> filename
    | None -> failwith "compiled evidence lacks its physical source filename"
  in
  let record sites loc reason =
    let start = loc.Location.loc_start and stop = loc.Location.loc_end in
    if
      reason = "" || loc.loc_ghost
      || start.Lexing.pos_cnum >= stop.Lexing.pos_cnum
      || Filename.basename start.pos_fname <> Filename.basename source
      || Filename.basename stop.pos_fname <> Filename.basename source
      || start.pos_fname <> compiled_filename
      || stop.pos_fname <> compiled_filename
    then failwith "diagnostic must identify a nonempty physical runner/routing site";
    sites := (loc, reason) :: !sites
  in
  let iterator =
    Transaction_runner.check ~caps ~emit:(record defects) ~undecided:(record unknown)
  in
  (match artifact.info.cmt_annots with
  | Cmt_format.Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "expected compiled implementation");
  (* Same-count reds deliberately corrupt sites, never category totals. *)
  (if Array.length Sys.argv = 7 then
     match (Sys.argv.(6), !defects) with
     | "--duplicate-defect-site", first :: _second :: rest ->
         defects := first :: first :: rest
     | "--wrong-defect-site", (loc, reason) :: rest ->
         let shift position = { position with Lexing.pos_cnum = position.pos_cnum + 1 } in
         defects :=
           ( { loc with loc_start = shift loc.loc_start; loc_end = shift loc.loc_end },
             reason )
           :: rest
     | _ -> failwith "invalid oracle control");
  if List.length !defects <> expected_defects || List.length !unknown <> expected_unknown
  then
    failwith
      (Printf.sprintf "%s: diagnostic category counts differ: expected %d/%d; got %d/%d"
         source expected_defects expected_unknown (List.length !defects)
         (List.length !unknown));
  let site category (loc, _) =
    let start = loc.Location.loc_start and stop = loc.Location.loc_end in
    Printf.sprintf "%s:%s:%d:%d:%d:%d" source category start.Lexing.pos_lnum
      (start.pos_cnum - start.pos_bol + 1)
      stop.Lexing.pos_lnum
      (stop.pos_cnum - stop.pos_bol + 1)
  in
  (* Columns are one-based; ends are exclusive. Sorting retains duplicates.
     Literal expectations are harness-owned data, not extracted from the typed tree. *)
  let expected =
    if Sys.argv.(5) = "-" then []
    else
      String.split_on_char ',' Sys.argv.(5)
      |> List.map (fun coordinates -> source ^ ":" ^ coordinates)
      |> List.sort String.compare
  in
  let actual =
    List.map (site "defect") !defects @ List.map (site "unknown") !unknown
    |> List.sort String.compare
  in
  if actual <> expected then
    failwith
      (Printf.sprintf "%s: exact diagnostic multiset mismatch: expected [%s]; got [%s]"
         source (String.concat ", " expected) (String.concat ", " actual))
