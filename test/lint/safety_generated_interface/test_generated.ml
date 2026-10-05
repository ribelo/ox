(* ^safe-y047 ^nlintcov-q6n2: exercise public Artifact source evidence with real CMTIs. *)
open Ocaml_common

let mutate ~(caps : < Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; .. >) script =
  match Ox_caps.Cap_unix.system ~caps ("bash " ^ Filename.quote script) with
  | Unix.WEXITED 0 -> ()
  | _ -> failwith "mutation command failed"

let () =
  let caps = Ox_caps_door.powerbox () in
  match Array.to_list Sys.argv with
  | _ :: mode :: root :: rest ->
      let mutation, paths =
        match (mode, rest) with
        | "after", script :: paths -> (Some script, paths)
        | _ -> (None, rest)
      in
      (if mode <> "uncached" then
         match Artifact.generated_sources ~caps ~root with
         | Ok _ -> ()
         | Error message -> failwith (root ^ ": " ^ message));
      Option.iter (mutate ~caps) mutation;
      List.iter
        (fun path ->
          try
            let artifact = Artifact.read ~caps path in
            let info = artifact.info in
            let info =
              match mode with
              | "incomplete-signature" ->
                  { info with cmt_annots = Cmt_format.Partial_interface [||] }
              | "nonempty-signature" ->
                  let donor =
                    Cmt_format.read_cmt
                      (Filename.concat root "evidence/dune__exe__Run.cmti")
                  in
                  { info with cmt_annots = donor.cmt_annots }
              | "missing-digest" -> { info with cmt_source_digest = None }
              | "stale-digest" ->
                  { info with cmt_source_digest = Some (Digest.string "stale") }
              | "missing-interface-digest" -> { info with cmt_interface_digest = None }
              | "missing-self-import" ->
                  let name = Compilation_unit.name info.cmt_modname in
                  {
                    info with
                    cmt_imports =
                      Array.of_list
                        (Array.to_list info.cmt_imports
                        |> List.filter (fun imported ->
                            not (Import_info.has_name imported ~name)));
                  }
              | _ -> info
            in
            let artifact = { artifact with info } in
            let actual = Artifact.authored_source ~caps artifact in
            if mode = "authored" then begin
              if actual <> Filename.concat root "run.mli" then
                failwith "authored source identity changed";
              if not (Array.exists (( = ) "-ppx") artifact.info.cmt_args) then
                failwith "actual compiler PPX invocation required";
              let markers = ref [] in
              Syntax.walk ~caps actual (fun _ base ->
                  {
                    base with
                    attribute =
                      (fun self a ->
                        if a.Parsetree.attr_name.txt = "ox.domain" then
                          markers :=
                            (a.attr_loc.loc_start.pos_fname, a.attr_loc.loc_start.pos_lnum)
                            :: !markers;
                        base.attribute self a);
                  });
              if !markers <> [ (actual, 1) ] then
                failwith "authored marker obligation disappeared";
              match artifact.info.cmt_annots with
              | Ocaml_common.Cmt_format.Interface signature when signature.sig_items = []
                ->
                  ()
              | _ -> failwith "expected PPX-erased typed signature"
            end
            else if actual <> Artifact.source artifact then
              failwith "not the physical compiler input";
            Artifact.check ~caps ~source:actual artifact;
            Artifact.setup ~caps artifact
          with ex -> failwith (path ^ ": " ^ Printexc.to_string ex))
        paths
  | _ -> failwith "expected MODE ROOT CMTI..."
