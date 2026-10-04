(* ^nlint-2nwm ^nlint-hxar: source-driven coverage and the spike's load-path plumbing. *)
open Ocaml_common
open Ox_caps

type t = { path : string; info : Cmt_format.cmt_infos; builddir : string }

let absolute ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let canonical ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  try Unix.realpath path with Unix.Unix_error _ -> absolute ~caps path

let rec project ~(caps : < Cap.fs_read ; .. >) dir =
  ignore caps#fs_read;
  if Sys.file_exists (Filename.concat dir "dune-project") then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else project ~caps parent

let read ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  let info = Cmt_format.read_cmt path in
  let builddir =
    if
      info.cmt_builddir = "/workspace_root"
      || String.starts_with ~prefix:"/workspace_root/" info.cmt_builddir
    then
      match project ~caps (Filename.dirname (absolute ~caps path)) with
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

let rec annotations ~(caps : < Cap.fs_read ; .. >) dir =
  if not (Sys.file_exists dir) then []
  else
    Array.to_list (Cap_sys.readdir ~caps dir)
    |> List.sort String.compare
    |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        if Sys.is_directory path then annotations ~caps path
        else if Filename.check_suffix path ".cmt" || Filename.check_suffix path ".cmti"
        then [ path ]
        else [])

let candidates ~(caps : < Cap.fs_read ; .. >) dir =
  match Hashtbl.find_opt cache dir with
  | Some xs -> xs
  | None ->
      let xs =
        List.map (fun path -> (path, lazy (read ~caps path))) (annotations ~caps dir)
      in
      Hashtbl.add cache dir xs;
      xs

let fixture ~caps path =
  let open Parsetree in
  Cap_stdlib.In_channel.with_open_bin ~caps path (fun channel ->
      Lexer.handle_docstrings := true;
      Docstrings.init ();
      Lexer.init ();
      let lexbuf = Lexing.from_channel channel in
      Location.init lexbuf path;
      let attributes =
        if Filename.check_suffix path ".mli" then
          (Parse.interface lexbuf).psg_items
          |> List.filter_map (fun item ->
              match item.psig_desc with
              | Psig_attribute attribute -> Some attribute
              | _ -> None)
        else
          Parse.implementation lexbuf
          |> List.filter_map (fun item ->
              match item.pstr_desc with
              | Pstr_attribute attribute -> Some attribute
              | _ -> None)
      in
      let markers =
        List.filter (fun a -> a.attr_name.txt = "ox_lint.fixture") attributes
      in
      match markers with
      | [] -> None
      | [
       {
         attr_payload =
           PStr
             [
               {
                 pstr_desc =
                   Pstr_eval
                     ( {
                         pexp_desc =
                           Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ };
                         _;
                       },
                       _ );
                 _;
               };
             ];
         _;
       };
      ] -> (
          match String.index_opt text ':' with
          | Some separator ->
              let rule = String.trim (String.sub text 0 separator) in
              let reason =
                String.trim
                  (String.sub text (separator + 1) (String.length text - separator - 1))
              in
              if rule = "" || reason = "" then
                failwith "fixture marker requires rule: reason";
              Some rule
          | None -> failwith "fixture marker requires rule: reason")
      | _ -> failwith "expected one file-level ox_lint.fixture string")

let relative ~root path =
  if path = root then ""
  else
    String.sub path (String.length root + 1) (String.length path - String.length root - 1)

type target = Library | Executable
type membership = Built of target | Data_only | Not_built | Unknown

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

(* [describe rules] uses ordinary, quoted S-expressions rather than csexp. *)
let parse_rules text =
  let length = String.length text in
  let delimiter = function ' ' | '\n' | '\r' | '\t' | '(' | ')' -> true | _ -> false in
  let rec items nested pos acc =
    if pos = length then
      if nested then failwith "truncated Dune rules" else (List.rev acc, pos)
    else
      match text.[pos] with
      | ' ' | '\n' | '\r' | '\t' -> items nested (pos + 1) acc
      | ';' ->
          items nested
            (Option.value (String.index_from_opt text pos '\n') ~default:length)
            acc
      | ')' ->
          if nested then (List.rev acc, pos + 1) else failwith "unexpected Dune close"
      | '(' ->
          let values, next = items true (pos + 1) [] in
          items nested next (List values :: acc)
      | '"' ->
          let rec stop i =
            if i >= length then failwith "truncated Dune string"
            else if text.[i] = '\\' then stop (i + 2)
            else if text.[i] = '"' then i
            else stop (i + 1)
          in
          let last = stop (pos + 1) in
          let value = Scanf.unescaped (String.sub text (pos + 1) (last - pos - 1)) in
          items nested (last + 1) (Atom value :: acc)
      | _ ->
          let rec stop i = if i = length || delimiter text.[i] then i else stop (i + 1) in
          let last = stop pos in
          items nested last (Atom (String.sub text pos (last - pos)) :: acc)
  in
  fst (items false 0 [])

let describe ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) root arguments =
  let command =
    "dune describe " ^ arguments ^ " --root " ^ Filename.quote root ^ " 2>/dev/null"
  in
  let channel = Cap_unix.open_process_in ~caps command in
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
  if Unix.close_process_in channel <> Unix.WEXITED 0 then
    failwith ("Dune inventory unavailable: describe " ^ arguments);
  Buffer.contents buffer

(* Dune 3.22's workspace description omits [test]/[tests]. Query declared
   compiler rules, not existing artifacts: missing CMTs must remain undecided.
   Recursive @check expands the lazy rules for all test modules, including helpers;
   Dune itself resolves ordered module sets, includes and preprocessing. *)
let rule_modules ~caps root resolve =
  describe ~caps root "rules --recursive @check"
  |> parse_rules
  |> List.concat_map (fun rule ->
      if field "targets" rule = None || field "deps" rule = None then
        failwith "Dune rule inventory has an invalid rule";
      match field "context" rule with
      | Some (Atom "default") -> (
          let targets =
            match Option.bind (field "targets" rule) (field "files") with
            | Some (List targets) -> targets
            | _ -> failwith "Dune rule inventory has invalid targets"
          in
          let annotation =
            List.find_map
              (function
                | Atom path
                  when Filename.check_suffix path ".cmt"
                       || Filename.check_suffix path ".cmti" ->
                    Some path
                | _ -> None)
              targets
          in
          match annotation with
          | None -> []
          | Some target -> (
              let kind =
                if
                  List.exists
                    (fun part -> Filename.check_suffix part ".eobjs")
                    (String.split_on_char '/' target)
                then Executable
                else Library
              in
              match field "deps" rule with
              | Some (List deps) ->
                  List.filter_map
                    (function
                      | List [ Atom "File"; List [ Atom "In_build_dir"; Atom path ] ]
                        when Filename.check_suffix path ".ml"
                             || Filename.check_suffix path ".mli" ->
                          Some (resolve (original path), kind)
                      | _ -> None)
                    deps
              | _ -> failwith "Dune rule inventory has invalid dependencies"))
      | None | Some (Atom _) -> []
      | Some (List _) -> failwith "Dune rule inventory has an invalid context")

let inventory_cache = Hashtbl.create 8

let inventory ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) root =
  match Hashtbl.find_opt inventory_cache root with
  | Some value -> value
  | None ->
      let value =
        try
          let description =
            describe ~caps root "workspace --format csexp --lang 0.1" |> parse_inventory
          in
          let resolve path =
            canonical ~caps
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
                        | Some (List [ Atom path ]) -> Some (resolve (original path), kind)
                        | Some (List []) -> None
                        | _ -> failwith "Dune inventory has an invalid source field")
                      [ "impl"; "intf" ])
                  modules
            | _ -> failwith "Dune inventory has no module list"
          in
          (match field "root" description with
          | Some (Atom described) when canonical ~caps described = root -> ()
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

let rule_inventory_cache = Hashtbl.create 8

let rule_inventory ~caps root =
  match Hashtbl.find_opt rule_inventory_cache root with
  | Some value -> value
  | None ->
      let value =
        try
          let resolve path =
            canonical ~caps
              (if Filename.is_relative path then Filename.concat root path else path)
          in
          Some (rule_modules ~caps root resolve)
        with
        | Failure _ | Invalid_argument _ | Scanf.Scan_failure _ | Sys_error _
        | Unix.Unix_error _
        ->
          None
      in
      Hashtbl.add rule_inventory_cache root value;
      value

(* Alias actions are absent from [describe rules] on Dune 3.22. Read their
   declared data dependencies, but let the compiler inventories take precedence. *)
let data_cache = Hashtbl.create 8

let data_dependencies ~caps root =
  match Hashtbl.find_opt data_cache root with
  | Some dependencies -> dependencies
  | None ->
      let read path =
        Cap_stdlib.In_channel.with_open_bin ~caps path In_channel.input_all
      in
      let rec stanzas seen path =
        if List.mem path seen then []
        else
          parse_rules (read path)
          |> List.concat_map (function
            | List [ Atom "include"; Atom included ] ->
                stanzas (path :: seen) (Filename.concat (Filename.dirname path) included)
            | stanza -> [ stanza ])
      in
      let rec directories dir =
        Array.to_list (Cap_sys.readdir ~caps dir)
        |> List.concat_map (fun name ->
            let path = Filename.concat dir name in
            if name = "_build" || name = ".git" then []
            else if Sys.is_directory path then directories path
            else if name <> "dune" then []
            else
              let resolve p = canonical ~caps (Filename.concat dir p) in
              let rec dependency = function
                | Atom p when not (String.contains p '%') -> [ (resolve p, false) ]
                | List [ Atom "source_tree"; Atom p ] when not (String.contains p '%') ->
                    [ (resolve p, true) ]
                | List [ Atom "file"; Atom p ] when not (String.contains p '%') ->
                    [ (resolve p, false) ]
                | List [ Atom "glob_files"; Atom pattern ]
                  when not (String.contains pattern '%') ->
                    let directory = resolve (Filename.dirname pattern) in
                    if not (Sys.file_exists directory) then []
                    else
                      Array.to_list (Cap_sys.readdir ~caps directory)
                      |> List.filter (fun name ->
                          Caps_policy.excluded [ Filename.basename pattern ] name)
                      |> List.map (fun name -> (Filename.concat directory name, false))
                | List (Atom name :: values) when String.starts_with ~prefix:":" name ->
                    List.concat_map dependency values
                | _ -> []
              in
              stanzas [] path
              |> List.concat_map (fun stanza ->
                  match stanza with
                  | List (_ :: fields) ->
                      List.concat_map
                        (function
                          | List (Atom "deps" :: dependencies) ->
                              List.concat_map dependency dependencies
                          | _ -> [])
                        fields
                  | _ -> []))
      in
      let dependencies = directories root in
      Hashtbl.add data_cache root dependencies;
      dependencies

let membership ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) input =
  let input = canonical ~caps input in
  match project ~caps (Filename.dirname input) with
  | None -> Unknown
  | Some root -> (
      match inventory ~caps root with
      | None -> Unknown
      | Some modules -> (
          let build = Filename.concat root "_build/default" in
          let expected =
            if String.starts_with ~prefix:(build ^ "/") input then input
            else canonical ~caps (Filename.concat build (relative ~root input))
          in
          match List.assoc_opt expected modules with
          | Some kind -> Built kind
          | None -> (
              match rule_inventory ~caps root with
              | None -> Unknown
              | Some modules -> (
                  match List.assoc_opt expected modules with
                  | Some kind -> Built kind
                  | None ->
                      let source =
                        if String.starts_with ~prefix:(build ^ "/") input then
                          Filename.concat root (relative ~root:build input)
                        else input
                      in
                      if
                        List.exists
                          (fun (path, tree) ->
                            source = path
                            || (tree && String.starts_with ~prefix:(path ^ "/") source))
                          (data_dependencies ~caps root)
                      then Data_only
                      else Not_built))))

let rec object_directories ~(caps : < Cap.fs_read ; .. >) ~root dir =
  let here =
    if not (Sys.file_exists dir) then []
    else
      Array.to_list (Cap_sys.readdir ~caps dir)
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
    if parent = dir then here else here @ object_directories ~caps ~root parent

let find ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) input =
  let input = canonical ~caps input in
  let suffix = if Filename.check_suffix input ".mli" then ".cmti" else ".cmt" in
  let sibling = Filename.remove_extension input ^ suffix in
  let same_source expected t =
    canonical ~caps (original (source t)) = canonical ~caps expected
  in
  let search expected dirs =
    List.find_map
      (fun dir ->
        List.find_map
          (fun (path, value) ->
            if Filename.check_suffix path suffix then
              let t = Lazy.force value in
              if same_source expected t then Some t else None
            else None)
          (candidates ~caps dir))
      dirs
  in
  if Sys.file_exists sibling then begin
    let t = read ~caps sibling in
    if not (same_source input t) then failwith "annotation belongs to another source";
    t
  end
  else
    match search input [ Filename.dirname input ] with
    | Some t -> t
    | None -> (
        let dirs, expected =
          match project ~caps (Filename.dirname input) with
          | Some root ->
              let build = Filename.concat root "_build/default" in
              let expected =
                if String.starts_with ~prefix:(build ^ "/") input then input
                else Filename.concat build (relative ~root input)
              in
              let dir = Filename.dirname expected in
              (dir :: object_directories ~caps ~root:build dir, expected)
          | None -> ([ Filename.dirname input ], input)
        in
        match search expected dirs with
        | Some t -> t
        | None ->
            let hint =
              match membership ~caps input with
              | Built Executable ->
                  "dune build @check (produces annotations for executable modules)"
              | _ ->
                  "dune build @install with -bin-annot; dune build @check for executable \
                   modules"
            in
            failwith ("missing typed annotation; run " ^ hint))

let digest ~(caps : < Cap.fs_read ; .. >) path =
  Cap_stdlib.In_channel.with_open_bin ~caps path (fun channel ->
      Digest.channel channel (-1))

let check ~(caps : < Cap.fs_read ; .. >) ~source:input t =
  let annotated = source t in
  (match t.info.cmt_source_digest with
  | Some expected when Sys.file_exists annotated && digest ~caps annotated = expected ->
      ()
  | Some _ -> failwith ("stale typed annotation: digest mismatch for " ^ annotated)
  | None -> failwith "typed annotation has no source digest");
  if canonical ~caps input <> canonical ~caps annotated then begin
    let built = original annotated in
    if (not (Sys.file_exists built)) || digest ~caps input <> digest ~caps built then
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

let setup ~(caps : < Cap.fs_read ; .. >) t =
  ignore caps#fs_read;
  Envaux.reset_cache ~preserve_persistent_env:false;
  let rebase p =
    if Filename.is_relative p then Filename.concat t.builddir p
    else if String.starts_with ~prefix:"/workspace_root/" p then
      Filename.concat t.builddir (String.sub p 16 (String.length p - 16))
    else p
  in
  let visible =
    List.map
      (fun (p : Clflags.visible_include) -> { p with path = rebase p.path })
      t.info.cmt_loadpath.visible
  in
  let hidden = List.map rebase t.info.cmt_loadpath.hidden in
  (* Dune installs private CMIs below the library's .private directory. In a
     build tree public_cmi omits them, while the sibling byte directory keeps
     all CMIs. Add these as hidden fallbacks, preserving recorded precedence. *)
  let private_dirs =
    List.map (fun (p : Clflags.visible_include) -> p.path) visible @ hidden
    |> List.concat_map (fun dir ->
        let installed = Filename.concat dir ".private" in
        let objects = Filename.dirname dir in
        let build =
          if Filename.basename dir = "public_cmi" && Filename.check_suffix objects ".objs"
          then [ Filename.concat objects "byte" ]
          else []
        in
        installed :: build)
    |> List.filter (fun dir -> Sys.file_exists dir && Sys.is_directory dir)
  in
  Load_path.init ~auto_include:Load_path.no_auto_include ~visible
    ~hidden:(hidden @ private_dirs);
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
