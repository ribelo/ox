(* ^safe-czoe ^safe-tlyw: use the real decider and checked artifacts for corpus review. *)
open Ocaml_common
open Ox_caps

let rec annotations ~caps path =
  if Sys.is_directory path then
    Array.to_list (Cap_sys.readdir ~caps path)
    |> List.concat_map (fun name -> annotations ~caps (Filename.concat path name))
  else if Filename.check_suffix path ".cmt" then [ path ]
  else []

let scan ~caps path =
  let artifact = Artifact.read ~caps path in
  if
    Option.fold ~none:false
      ~some:(fun name -> Filename.check_suffix name ".ml-gen")
      artifact.info.cmt_sourcefile
  then None
  else
    let source = Artifact.authored_source ~caps artifact in
    Artifact.check ~caps ~source artifact;
    Artifact.setup ~caps artifact;
    let count = ref 0 in
    let iterator =
      Function_comparison.check ~caps (fun location ->
          incr count;
          Cap_stdlib.printf ~caps
            "%s:%d:%d: unsupported structural comparison of functions\n" source
            location.Location.loc_start.Lexing.pos_lnum
            (location.loc_start.pos_cnum - location.loc_start.pos_bol))
    in
    (match artifact.info.cmt_annots with
    | Implementation structure -> iterator.structure iterator structure
    | _ -> failwith ("incomplete implementation evidence: " ^ path));
    Some !count

let run ~(caps : < Cap.fs_read ; Cap.stdout >) =
  let paths = List.tl (Array.to_list Sys.argv) |> List.concat_map (annotations ~caps) in
  if paths = [] then failwith "supply built annotation directories or CMTs";
  let counts = List.filter_map (scan ~caps) paths in
  let findings = List.fold_left ( + ) 0 counts in
  Cap_stdlib.printf ~caps
    "Reviewed %d complete implementations; %d findings; %d generated wrappers excluded.\n"
    (List.length counts) findings
    (List.length paths - List.length counts)

let () =
  let powerbox = Ox_test.powerbox () in
  run ~caps:(powerbox :> < Cap.fs_read ; Cap.stdout >)
