(* ^safe-eeso ^safe-doj9 ^safe-2led ^safe-fr73 ^safe-y047 ^safe-tlyw *)
open Ocaml_common

let sites ~caps name =
  let source = "evidence/" ^ String.lowercase_ascii name ^ ".ml" in
  let path =
    "evidence/.function_comparison_fixtures.objs/byte/function_comparison_fixtures__"
    ^ name ^ ".cmt"
  in
  let artifact = Artifact.read ~caps path in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let sites = ref [] in
  let iterator =
    Function_comparison.check ~caps (fun loc ->
        let start = loc.Location.loc_start in
        sites := (start.Lexing.pos_lnum, start.pos_cnum - start.pos_bol) :: !sites)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "expected complete implementation evidence");
  List.sort Stdlib.compare !sites

let expect name expected actual =
  let show (line, column) = Printf.sprintf "%d:%d" line column in
  if expected <> actual then
    failwith
      (Printf.sprintf "%s: expected [%s], got [%s]" name
         (String.concat ";" (List.map show expected))
         (String.concat ";" (List.map show actual)))

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read >) in
  expect "direct arrow comparisons"
    [
      (2, 31);
      (3, 33);
      (4, 30);
      (5, 33);
      (6, 36);
      (7, 39);
      (8, 34);
      (12, 38);
      (16, 2);
      (19, 36);
      (21, 39);
      (25, 2);
      (29, 2);
      (31, 40);
      (36, 2);
      (40, 35);
      (43, 2);
    ]
    (sites ~caps "Bad");
  expect "physical, dedicated, shadowed, data and horizon controls" []
    (sites ~caps "Good")
