(* ^ncapslint-8jcy: argument payloads are clean; identical ambient shapes fail. *)
open Ocaml_common

let sites ~caps source =
  let dir = Filename.dirname source in
  let kind = Filename.basename dir in
  let unit_name =
    String.capitalize_ascii (Filename.remove_extension (Filename.basename source))
  in
  let annotation =
    Printf.sprintf "%s/.caps_%s.objs/byte/caps_%s__%s.cmt" dir kind kind unit_name
  in
  let artifact = Artifact.read ~caps annotation in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let found = ref [] in
  let iterator =
    Caps.signature ~caps (fun loc ->
        found := loc.Location.loc_start.Lexing.pos_lnum :: !found)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "implementation required");
  List.sort_uniq Int.compare !found

let expect ~caps source expected =
  let actual = sites ~caps source in
  if actual <> expected then
    failwith
      (Printf.sprintf "%s: expected signature sites [%s], got [%s]" source
         (String.concat "; " (List.map string_of_int expected))
         (String.concat "; " (List.map string_of_int actual)))

let run ~(caps : < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout ; Ox_caps.Cap.time ; .. >) ()
    =
  (* ^ncapslint-8jcy: 18 shared binary variants must remain a graph walk.
     The old path-local traversal takes about 1.8 seconds here; the visited-state
     traversal takes under 0.1. A one-second CPU bound leaves wide headroom. *)
  let before = Ox_caps.Cap_sys.time ~caps () in
  expect ~caps "clean/signature.ml" [];
  if Ox_caps.Cap_sys.time ~caps () -. before > 1.0 then
    failwith "shared payload graph unfolded as a tree";
  expect ~caps "violating/signature.ml" [ 4; 6; 10 ];
  expect ~caps "violating/signature_payloads.ml"
    [ 7; 19; 24; 31; 35; 43; 47; 49; 51; 57; 64; 66; 71; 82 ];
  Ox_caps.Cap_stdlib.print_endline ~caps
    "parameter payload provenance and ambient/mint/impostor boundaries: pass"

let () =
  let powerbox = Ox_test.powerbox () in
  let caps =
    (powerbox :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout ; Ox_caps.Cap.time >)
  in
  run ~caps ()
