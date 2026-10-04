(* ^nlintd-a7oq: reproducible inventory from exactly the rules' typed predicate. *)
open Ocaml_common

let rec files path =
  if Sys.is_directory path then
    Array.to_list (Sys.readdir path)
    |> List.sort String.compare
    |> List.concat_map (fun name -> files (Filename.concat path name))
  else if Filename.check_suffix path ".mli" then [ path ]
  else []

let () =
  let total, selected = (ref 0, ref 0) in
  Array.to_list Sys.argv |> List.tl |> List.concat_map files
  |> List.iter (fun source ->
      let artifact = Artifact.find source in
      Artifact.check ~source artifact;
      Artifact.setup artifact;
      let iterator =
        Interface_docs.iterator (fun value ->
            incr total;
            if value.families <> [] then begin
              incr selected;
              Printf.printf "%s\t%d\t%s\t%s\t%b\t%b\n" source
                value.loc.Location.loc_start.pos_lnum value.name
                (String.concat "," value.families)
                value.behaviour value.cancel_safety
            end)
      in
      match artifact.info.cmt_annots with
      | Interface tree -> iterator.signature iterator tree
      | _ -> failwith "expected interface");
  Printf.eprintf "interface inventory: %d selected / %d vals\n" !selected !total
