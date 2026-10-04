(* ^nlint-2nwm ^nlint-hxar: source-driven coverage and the spike's load-path plumbing. *)
open Ocaml_common

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

let absolute path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let canonical path = try Unix.realpath path with Unix.Unix_error _ -> absolute path

let rec project dir =
  if Sys.file_exists (Filename.concat dir "dune-project") then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else project parent

let read path =
  let info = Cmt_format.read_cmt path in
  let builddir =
    if
      info.cmt_builddir = "/workspace_root"
      || String.starts_with ~prefix:"/workspace_root/" info.cmt_builddir
    then
      match project (Filename.dirname (absolute path)) with
      | Some root ->
          let base = Filename.concat root "_build/default" in
          if info.cmt_builddir = "/workspace_root" then base
          else
            Filename.concat base
              (String.sub info.cmt_builddir 16 (String.length info.cmt_builddir - 16))
      | None -> failwith "cannot rebase /workspace_root: no dune-project found"
    else info.cmt_builddir
  in
  { path; info; builddir }

let source t =
  match t.info.cmt_sourcefile with
  | Some path ->
      if Filename.is_relative path then Filename.concat t.builddir path else path
  | None -> failwith "annotation has no source filename"

let original path =
  if Filename.check_suffix path ".pp.ml" then Filename.chop_suffix path ".pp.ml" ^ ".ml"
  else if Filename.check_suffix path ".pp.mli" then
    Filename.chop_suffix path ".pp.mli" ^ ".mli"
  else path

let cache = Hashtbl.create 32

let rec annotations dir =
  if not (Sys.file_exists dir) then []
  else
    Array.to_list (Sys.readdir dir)
    |> List.sort String.compare
    |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        if Sys.is_directory path then annotations path
        else if Filename.check_suffix path ".cmt" || Filename.check_suffix path ".cmti"
        then [ path ]
        else [])

let candidates dir =
  match Hashtbl.find_opt cache dir with
  | Some xs -> xs
  | None ->
      let xs = List.map (fun path -> (path, lazy (read path))) (annotations dir) in
      Hashtbl.add cache dir xs;
      xs

let relative ~root path =
  if path = root then ""
  else
    String.sub path (String.length root + 1) (String.length path - String.length root - 1)

let find input =
  let input = absolute input in
  let suffix = if Filename.check_suffix input ".mli" then ".cmti" else ".cmt" in
  let sibling = Filename.remove_extension input ^ suffix in
  let relevant path =
    let stem =
      String.lowercase_ascii (Filename.remove_extension (Filename.basename input))
    in
    let file = String.lowercase_ascii (Filename.basename path) in
    file = stem ^ suffix || String.ends_with ~suffix:("__" ^ stem ^ suffix) file
  in
  if Sys.file_exists sibling then begin
    let t = read sibling in
    if canonical (original (source t)) <> canonical input then
      failwith "annotation belongs to another source";
    t
  end
  else
    let local =
      List.find_map
        (fun (path, value) ->
          if relevant path then
            let t = Lazy.force value in
            if canonical (original (source t)) = canonical input then Some t else None
          else None)
        (candidates (Filename.dirname input))
    in
    match local with
    | Some t -> t
    | None -> (
        let root = project (Filename.dirname input) in
        let dir, expected =
          match root with
          | Some root ->
              let build = Filename.concat root "_build/default" in
              ( Filename.concat build (relative ~root (Filename.dirname input)),
                Filename.concat build (relative ~root input) )
          | None -> (Filename.dirname input, input)
        in
        let matches =
          List.filter_map
            (fun (path, value) ->
              if relevant path then
                let t = Lazy.force value in
                if canonical (original (source t)) = canonical expected then Some t
                else None
              else None)
            (candidates dir)
        in
        match matches with
        | t :: _ -> t
        | [] ->
            failwith "missing typed annotation; run dune build @install with -bin-annot")

let check ~source:input t =
  let annotated = source t in
  (match t.info.cmt_source_digest with
  | Some digest when Sys.file_exists annotated && Digest.file annotated = digest -> ()
  | Some _ -> failwith ("stale typed annotation: digest mismatch for " ^ annotated)
  | None -> failwith "typed annotation has no source digest");
  if canonical input <> canonical annotated then begin
    let built = original annotated in
    if (not (Sys.file_exists built)) || Digest.file input <> Digest.file built then
      failwith ("stale typed annotation: original source differs from build copy " ^ input);
    if (Unix.stat input).st_mtime > (Unix.stat t.path).st_mtime then
      failwith ("stale typed annotation: source is newer than annotation " ^ input)
  end;
  match t.info.cmt_annots with
  | Implementation _ when Filename.check_suffix input ".ml" -> ()
  | Interface _ when Filename.check_suffix input ".mli" -> ()
  | _ ->
      failwith
        "annotation is not a complete implementation/interface of the requested source"

let setup t =
  Envaux.reset_cache ~preserve_persistent_env:false;
  let rebase p =
    if Filename.is_relative p then Filename.concat t.builddir p
    else if String.starts_with ~prefix:"/workspace_root/" p then
      Filename.concat t.builddir (String.sub p 16 (String.length p - 16))
    else p
  in
  Load_path.init ~auto_include:Load_path.no_auto_include
    ~visible:
      (List.map
         (fun (p : Clflags.visible_include) -> { p with path = rebase p.path })
         t.info.cmt_loadpath.visible)
    ~hidden:(List.map rebase t.info.cmt_loadpath.hidden);
  (* Missing CMIs can make expand_head retain an alias rather than fail. Validate
     the annotation's imported fingerprints before any type predicate can pass. *)
  Array.iter
    (fun imported ->
      let unit_name = Import_info.name imported in
      let name = Compilation_unit.Name.to_string unit_name in
      match Import_info.crc imported with
      | None -> ()
      | Some expected -> (
          let filename = String.uncapitalize_ascii name ^ ".cmi" in
          let path =
            try Load_path.find filename
            with Not_found ->
              failwith ("missing imported CMI " ^ name ^ "; rebuild typed evidence")
          in
          let info = Cmi_format.read_cmi path in
          match
            Array.find_opt
              (fun imported -> Import_info.has_name imported ~name:unit_name)
              info.cmi_crcs
          with
          | Some imported when Import_info.crc imported = Some expected -> ()
          | _ ->
              failwith
                ("stale typed annotation: imported CMI fingerprint changed for " ^ name)))
    t.info.cmt_imports
