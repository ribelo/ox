(* ^ncapslint-8jcy: argument payloads are clean; identical ambient shapes fail. *)
open Ocaml_common

let sites source =
  let dir = Filename.dirname source in
  let kind = Filename.basename dir in
  let unit_name =
    String.capitalize_ascii (Filename.remove_extension (Filename.basename source))
  in
  let annotation =
    Printf.sprintf "%s/.caps_%s.objs/byte/caps_%s__%s.cmt" dir kind kind unit_name
  in
  let artifact = Artifact.read annotation in
  Artifact.check ~source artifact;
  Artifact.setup artifact;
  let found = ref [] in
  let iterator =
    Caps.signature (fun loc -> found := loc.Location.loc_start.Lexing.pos_lnum :: !found)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "implementation required");
  List.sort_uniq Int.compare !found

let expect source expected =
  let actual = sites source in
  if actual <> expected then
    failwith
      (Printf.sprintf "%s: expected signature sites [%s], got [%s]" source
         (String.concat "; " (List.map string_of_int expected))
         (String.concat "; " (List.map string_of_int actual)))

let () =
  (* ^ncapslint-8jcy: 18 shared binary variants must remain a graph walk.
     The old path-local traversal takes about 1.8 seconds here; the visited-state
     traversal takes under 0.1. A one-second CPU bound leaves wide headroom. *)
  let before = Sys.time () in
  expect "clean/signature.ml" [];
  if Sys.time () -. before > 1.0 then failwith "shared payload graph unfolded as a tree";
  expect "violating/signature.ml" [ 3; 5; 9 ];
  expect "violating/signature_payloads.ml"
    [ 6; 18; 23; 30; 34; 42; 46; 48; 50; 56; 63; 65; 70; 81 ];
  print_endline "parameter payload provenance and ambient/mint/impostor boundaries: pass"
