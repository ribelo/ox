(* ^safe-y047 ^nlintcov-q6n2: validate real installed annotations, not synthetic records. *)
open Ocaml_common

let check ~caps path =
  let raw = Cmt_format.read_cmt path in
  let artifact = Artifact.read ~caps path in
  if
    raw.cmt_sourcefile <> artifact.info.cmt_sourcefile
    || raw.cmt_builddir <> artifact.info.cmt_builddir
    || raw.cmt_args <> artifact.info.cmt_args
    || raw.cmt_loadpath <> artifact.info.cmt_loadpath
  then failwith "installed resolution rewrote compiler metadata";
  let source = Artifact.authored_source ~caps artifact in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let paths = Load_path.get_paths () in
  if
    List.length paths.visible <> List.length raw.cmt_loadpath.visible
    || List.length paths.hidden <> List.length raw.cmt_loadpath.hidden
  then failwith "installed load-path slots were added or removed";
  List.iter2
    (fun (recorded : Clflags.visible_include) (resolved : Clflags.visible_include) ->
      if recorded.path = "" && resolved.path <> "/dev/null" then
        failwith "unavailable cwd slot was rebound";
      if recorded.cmx_guaranteed <> resolved.cmx_guaranteed then
        failwith "load-path visibility metadata changed")
    raw.cmt_loadpath.visible paths.visible;
  let name = Compilation_unit.name_as_string raw.cmt_modname in
  let actual = Load_path.find (String.uncapitalize_ascii name ^ ".cmi") in
  if Filename.dirname actual <> Filename.dirname path then
    failwith ("own CMI escaped installed directory: " ^ actual)

let () =
  let caps = Ox_caps_door.powerbox () in
  match Array.to_list Sys.argv with
  | _ :: paths when paths <> [] -> List.iter (check ~caps) paths
  | _ -> failwith "expected installed annotation paths"
