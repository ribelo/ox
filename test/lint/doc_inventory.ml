(* ^nlintd-a7oq: reproducible inventory from exactly the rules' typed predicate. *)
open Ocaml_common
open Ox_caps

let rec files ~(caps : < Cap.fs_read ; .. >) path =
  if Sys.is_directory path then
    Array.to_list (Cap_sys.readdir ~caps path)
    |> List.sort String.compare
    |> List.concat_map (fun name -> files ~caps (Filename.concat path name))
  else if Filename.check_suffix path ".mli" then [ path ]
  else []

let run ~(caps : < Cap.fork ; Cap.exec ; Cap.fs_read ; Cap.stdout ; Cap.stderr ; .. >) =
  let total, selected = (ref 0, ref 0) in
  Array.to_list Sys.argv |> List.tl
  |> List.concat_map (files ~caps)
  |> List.iter (fun source ->
      let artifact = Artifact.find ~caps source in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact;
      let iterator =
        Interface_docs.iterator ~caps (fun value ->
            incr total;
            if value.families <> [] then begin
              incr selected;
              Cap_stdlib.printf ~caps "%s\t%d\t%s\t%s\t%b\t%b\n" source
                value.loc.Location.loc_start.pos_lnum value.name
                (String.concat "," value.families)
                value.behaviour value.cancel_safety
            end)
      in
      match artifact.info.cmt_annots with
      | Interface tree -> iterator.signature iterator tree
      | _ -> failwith "expected interface");
  Cap_stdlib.eprintf ~caps "interface inventory: %d selected / %d vals\n" !selected !total

let () = run ~caps:(Ox_caps_door.powerbox ())
