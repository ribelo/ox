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

type target = Library | Executable
type membership = Built of target | Not_built | Unknown

(* Dune's declared modules distinguish excluded sources from missing annotations.
   A failed/unavailable inventory is not evidence that a file is excluded. *)
type sexp = Atom of string | List of sexp list

let parse_inventory text =
  let cursor = ref 0 in
  let rec parse () =
    if !cursor >= String.length text then failwith "truncated Dune inventory";
    if text.[!cursor] = '(' then begin
      incr cursor;
      let rec items acc =
        if !cursor >= String.length text then failwith "truncated Dune inventory";
        if text.[!cursor] = ')' then (
          incr cursor;
          List (List.rev acc))
        else items (parse () :: acc)
      in
      items []
    end
    else begin
      let start = !cursor in
      while
        !cursor < String.length text && text.[!cursor] >= '0' && text.[!cursor] <= '9'
      do
        incr cursor
      done;
      if start = !cursor || !cursor >= String.length text || text.[!cursor] <> ':' then
        failwith "invalid Dune inventory";
      let length = int_of_string (String.sub text start (!cursor - start)) in
      incr cursor;
      if length > String.length text - !cursor then failwith "truncated Dune inventory";
      let atom = String.sub text !cursor length in
      cursor := !cursor + length;
      Atom atom
    end
  in
  let value = parse () in
  if !cursor <> String.length text then failwith "trailing Dune inventory data";
  value

let field name = function
  | List fields ->
      List.find_map
        (function List [ Atom key; value ] when key = name -> Some value | _ -> None)
        fields
  | Atom _ -> None

let inventory_cache = Hashtbl.create 8

let inventory root =
  match Hashtbl.find_opt inventory_cache root with
  | Some value -> value
  | None ->
      let value =
        try
          let command =
            "dune describe workspace --root " ^ Filename.quote root
            ^ " --format csexp --lang 0.1 2>/dev/null"
          in
          let channel = Unix.open_process_in command in
          let buffer = Buffer.create 4096 in
          (try
             try
               while true do
                 Buffer.add_channel buffer channel 4096
               done
             with End_of_file -> ()
           with ex ->
             ignore (Unix.close_process_in channel);
             raise ex);
          let status = Unix.close_process_in channel in
          if status <> Unix.WEXITED 0 then None
          else
            let resolve path =
              canonical
                (if Filename.is_relative path then Filename.concat root path else path)
            in
            let modules kind fields =
              match field "modules" fields with
              | Some (List modules) ->
                  List.concat_map
                    (fun fields ->
                      List.filter_map
                        (fun key ->
                          match field key fields with
                          | Some (List [ Atom path ]) ->
                              Some (resolve (original path), kind)
                          | Some (List []) -> None
                          | _ -> failwith "Dune inventory has an invalid source field")
                        [ "impl"; "intf" ])
                    modules
              | _ -> failwith "Dune inventory has no module list"
            in
            let description = parse_inventory (Buffer.contents buffer) in
            (match field "root" description with
            | Some (Atom described) when canonical described = root -> ()
            | _ -> failwith "Dune inventory has an invalid root");
            (match field "build_context" description with
            | Some (Atom "_build/default") -> ()
            | _ -> failwith "Dune inventory is not the default build context");
            match description with
            | List entries ->
                Some
                  (List.concat_map
                     (function
                       | List [ Atom "library"; fields ] -> modules Library fields
                       | List [ Atom "executables"; fields ] -> modules Executable fields
                       | _ -> [])
                     entries)
            | Atom _ -> None
        with Failure _ | Invalid_argument _ | Sys_error _ | Unix.Unix_error _ -> None
      in
      Hashtbl.add inventory_cache root value;
      value

let membership input =
  let input = canonical input in
  match project (Filename.dirname input) with
  | None -> Unknown
  | Some root -> (
      match inventory root with
      | None -> Unknown
      | Some modules -> (
          let build = Filename.concat root "_build/default" in
          let expected =
            if String.starts_with ~prefix:(build ^ "/") input then input
            else canonical (Filename.concat build (relative ~root input))
          in
          match List.assoc_opt expected modules with
          | Some kind -> Built kind
          | None -> Not_built))

let rec object_directories ~root dir =
  let here =
    if not (Sys.file_exists dir) then []
    else
      Array.to_list (Sys.readdir dir)
      |> List.sort String.compare
      |> List.filter_map (fun name ->
          let path = Filename.concat dir name in
          if
            (Filename.check_suffix name ".objs" || Filename.check_suffix name ".eobjs")
            && Sys.is_directory path
          then Some path
          else None)
  in
  if dir = root then here
  else
    let parent = Filename.dirname dir in
    if parent = dir then here else here @ object_directories ~root parent

let find input =
  let input = canonical input in
  let suffix = if Filename.check_suffix input ".mli" then ".cmti" else ".cmt" in
  let sibling = Filename.remove_extension input ^ suffix in
  let same_source expected t = canonical (original (source t)) = canonical expected in
  let search expected dirs =
    List.find_map
      (fun dir ->
        List.find_map
          (fun (path, value) ->
            if Filename.check_suffix path suffix then
              let t = Lazy.force value in
              if same_source expected t then Some t else None
            else None)
          (candidates dir))
      dirs
  in
  if Sys.file_exists sibling then begin
    let t = read sibling in
    if not (same_source input t) then failwith "annotation belongs to another source";
    t
  end
  else
    match search input [ Filename.dirname input ] with
    | Some t -> t
    | None -> (
        let dirs, expected =
          match project (Filename.dirname input) with
          | Some root ->
              let build = Filename.concat root "_build/default" in
              let expected =
                if String.starts_with ~prefix:(build ^ "/") input then input
                else Filename.concat build (relative ~root input)
              in
              let dir = Filename.dirname expected in
              (dir :: object_directories ~root:build dir, expected)
          | None -> ([ Filename.dirname input ], input)
        in
        match search expected dirs with
        | Some t -> t
        | None ->
            let hint =
              match membership input with
              | Built Executable ->
                  "dune build @check (produces annotations for executable modules)"
              | _ ->
                  "dune build @install with -bin-annot; dune build @check for executable \
                   modules"
            in
            failwith ("missing typed annotation; run " ^ hint))

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
