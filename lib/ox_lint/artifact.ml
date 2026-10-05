(* ^nlint-2nwm ^nlint-hxar: source-driven coverage and the spike's load-path plumbing. *)
open Ocaml_common
open Ox_caps

type load_directory = Mapped_directory of string | Unavailable_original_cwd

type origin =
  | Build
  | Installed of {
      source_path : string;
      own_objects : string;
      directory : string;
      manifest_root : string;
      annotations : string list;
    }

type t = {
  path : string;
  info : Cmt_format.cmt_infos;
  builddir : string;
  origin : origin;
}

let absolute ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let ignored ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) ~directory names =
  let rec query = function
    | [] -> []
    | names ->
        let batch, rest = (List.take 128 names, List.drop 128 names) in
        let command =
          "printf '%s\\0' "
          ^ String.concat " " (List.map Filename.quote batch)
          ^ " | git -C " ^ Filename.quote directory
          ^ " check-ignore --stdin -z 2>/dev/null"
        in
        let channel = Cap_unix.open_process_in ~caps command in
        let output =
          try In_channel.input_all channel
          with ex ->
            ignore (Unix.close_process_in channel);
            raise ex
        in
        let ignored =
          match Unix.close_process_in channel with
          | Unix.WEXITED 0 ->
              String.split_on_char '\000' output |> List.filter (( <> ) "")
          | _ -> []
        in
        ignored @ query rest
  in
  query names

let canonical ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  try Unix.realpath path with Unix.Unix_error _ -> absolute ~caps path

let rec project ~(caps : < Cap.fs_read ; .. >) dir =
  ignore caps#fs_read;
  if Sys.file_exists (Filename.concat dir "dune-project") then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else project ~caps parent

(* ^nlintcov-q6n2: nested projects are scan boundaries, not necessarily build
   workspaces. An outer Dune invocation compiles them into its own _build tree. *)
let workspace ~(caps : < Cap.fs_read ; .. >) input =
  let input = absolute ~caps input in
  let directory =
    if Sys.file_exists input && Sys.is_directory input then input
    else Filename.dirname input
  in
  let rec build_owner directory =
    let parent = Filename.dirname directory in
    if Filename.basename directory = "default" && Filename.basename parent = "_build" then
      Some (Filename.dirname parent)
    else if parent = directory then None
    else build_owner parent
  in
  match build_owner directory with
  | Some root -> Some root
  | None -> (
      let rec projects directory =
        let here =
          if Sys.file_exists (Filename.concat directory "dune-project") then [ directory ]
          else []
        in
        let parent = Filename.dirname directory in
        if parent = directory then here else here @ projects parent
      in
      let roots = projects directory in
      match
        List.find_opt
          (fun root ->
            let relative =
              String.sub input
                (String.length root + 1)
                (String.length input - String.length root - 1)
            in
            Sys.file_exists
              (Filename.concat (Filename.concat root "_build/default") relative))
          (List.filter (fun root -> String.length input > String.length root) roots)
      with
      | Some _ as root -> root
      | None -> List.find_opt (fun _ -> true) roots)

let original path =
  if Filename.check_suffix path ".pp.ml" then Filename.chop_suffix path ".pp.ml" ^ ".ml"
  else if Filename.check_suffix path ".pp.mli" then
    Filename.chop_suffix path ".pp.mli" ^ ".mli"
  else path

let cache = Hashtbl.create 32

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

(* ^safe-y047 ^nlintcov-q6n2: Dune additionally escapes literal interpolation
   openers as [\%{]. Consume escape pairs so an escaped backslash cannot turn
   the following percent into an escape. Keep Scanf's validation for all other
   escapes, including malformed decimal and unknown escapes. *)
let dune_unescaped text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let rec copy pos =
    if pos < length then
      if text.[pos] = '\\' && pos + 1 < length then begin
        if text.[pos + 1] = '%' && pos + 2 < length && text.[pos + 2] = '{' then
          Buffer.add_char buffer '%'
        else begin
          Buffer.add_char buffer text.[pos];
          Buffer.add_char buffer text.[pos + 1]
        end;
        copy (pos + 2)
      end
      else begin
        Buffer.add_char buffer text.[pos];
        copy (pos + 1)
      end
  in
  copy 0;
  Scanf.unescaped (Buffer.contents buffer)

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
          let value = dune_unescaped (String.sub text (pos + 1) (last - pos - 1)) in
          items nested (last + 1) (Atom value :: acc)
      | _ ->
          let rec stop i = if i = length || delimiter text.[i] then i else stop (i + 1) in
          let last = stop pos in
          items nested last (Atom (String.sub text pos (last - pos)) :: acc)
  in
  fst (items false 0 [])

(* ^safe-y047 ^nlintcov-q6n2: installation is proved by the adjacent package
   manifest, never by a checkout, a basename search or an installation prefix guess.
   One parent permits Dune's public sublibraries (for example eio/core). *)
let installed_origin ~(caps : < Cap.fs_read ; .. >) path info =
  let require condition message =
    if not condition then failwith ("installed artifact: " ^ message)
  in
  let directory = Filename.dirname (canonical ~caps path) in
  let manifests =
    [ directory; Filename.dirname directory ]
    |> List.sort_uniq String.compare
    |> List.map (fun dir -> Filename.concat dir "dune-package")
    |> List.filter Sys.file_exists
  in
  match manifests with
  | [] -> None
  | [ manifest ] ->
      require (canonical ~caps manifest = manifest) "symlink package manifest";
      let root = Filename.dirname manifest in
      let one key fields =
        match
          List.filter_map
            (function
              | List (Atom name :: values) when name = key -> Some values | _ -> None)
            fields
        with
        | [ values ] -> values
        | _ -> failwith ("installed artifact: missing/ambiguous " ^ key)
      in
      let atom key fields =
        match one key fields with
        | [ Atom value ] -> value
        | _ -> failwith ("installed artifact: invalid " ^ key)
      in
      let safe_relative relative =
        require
          (Filename.is_relative relative
          && List.for_all
               (fun part -> part <> "" && part <> "." && part <> "..")
               (String.split_on_char '/' relative))
          ("escaping manifest path " ^ relative);
        let full = Filename.concat root relative in
        require
          (String.starts_with ~prefix:(root ^ "/") (canonical ~caps full))
          ("escaping installed file " ^ relative);
        require (canonical ~caps full = full) ("symlink manifest claim " ^ relative);
        full
      in
      let contents =
        Cap_stdlib.In_channel.with_open_bin ~caps manifest In_channel.input_all
        |> parse_rules
      in
      let files =
        match one "lib" (one "files" contents) with
        | [ List files ] ->
            List.map
              (function
                | Atom path -> path | _ -> failwith "installed artifact: invalid files")
              files
        | _ -> failwith "installed artifact: invalid lib files"
      in
      let owned relative =
        require
          (List.length (List.filter (( = ) relative) files) = 1)
          ("unlisted/ambiguous installed file " ^ relative);
        safe_relative relative
      in
      let object_name = Filename.remove_extension (Filename.basename path) in
      require
        (Compilation_unit.name_as_string info.Cmt_format.cmt_modname
        = String.capitalize_ascii object_name)
        "annotation compilation unit differs from its object name";
      let rec modules = function
        | List (Atom ("module" | "alias" | "singleton") :: fields) ->
            if atom "obj_name" fields = object_name then [ fields ] else []
        | List values -> List.concat_map modules values
        | Atom _ -> []
      in
      let candidates =
        List.concat_map
          (function
            | List (Atom "library" :: fields) -> List.concat_map modules fields | _ -> [])
          contents
      in
      let fields =
        match candidates with
        | [ fields ] -> fields
        | _ -> failwith "installed artifact: missing/ambiguous owning module"
      in
      require (atom "visibility" fields = "public") "unsupported private module";
      let kind = if Filename.check_suffix path ".cmti" then "intf" else "impl" in
      require
        (Filename.check_suffix path ".cmt" || Filename.check_suffix path ".cmti")
        "unsupported annotation extension";
      let declared = atom "path" (one kind (one "source" fields)) in
      let recorded =
        match info.cmt_sourcefile with
        | Some path -> path
        | None -> failwith "installed artifact: missing compiler source"
      in
      require
        (Filename.basename recorded = Filename.basename declared)
        "compiled input differs from installed source (preprocessing unsupported)";
      require
        (not
           (Array.exists (fun arg -> String.starts_with ~prefix:"-pp" arg) info.cmt_args))
        "preprocessed compiler input is not an installed plain source";
      let source_name =
        if Filename.check_suffix declared ".ml-gen" then begin
          require (atom "kind" fields = "alias") "unsupported generated source";
          Filename.chop_suffix declared "-gen"
        end
        else declared
      in
      let source_path = owned source_name in
      let annotation =
        Filename.concat (Filename.dirname source_name) (Filename.basename path)
      in
      let annotation =
        if Filename.dirname source_name = "." then Filename.basename path else annotation
      in
      require
        (canonical ~caps (owned annotation) = canonical ~caps path)
        "annotation is outside its owning module directory";
      ignore
        (owned
           (if Filename.dirname annotation = "." then object_name ^ ".cmi"
            else Filename.concat (Filename.dirname annotation) (object_name ^ ".cmi")));
      let rec outputs = function
        | "-o" :: output :: rest -> output :: outputs rest
        | _ :: rest -> outputs rest
        | [] -> []
      in
      let output =
        match outputs (Array.to_list info.cmt_args) with
        | [ output ]
          when Filename.remove_extension (Filename.basename output) = object_name ->
            output
        | _ -> failwith "installed artifact: missing/ambiguous own compiler output"
      in
      let own_objects = Filename.dirname output in
      require
        (List.exists
           (fun (p : Clflags.visible_include) -> p.path = own_objects)
           info.cmt_loadpath.visible
        || List.mem own_objects info.cmt_loadpath.hidden)
        "own compiler directory absent from load path";
      let annotations =
        List.filter (fun name -> Filename.check_suffix name ".cmt") files
        |> List.map safe_relative
      in
      Some
        (Installed
           { source_path; own_objects; directory; manifest_root = root; annotations })
  | _ -> failwith "installed artifact: ambiguous adjacent package manifests"

(* A relative sibling directory is mapped only by that sibling's own compiled
   output and manifest-owned source. No recursive environment setup is involved. *)
let installed_sibling ~caps t requested =
  match t.origin with
  | Build -> None
  | Installed { manifest_root; annotations; _ } -> (
      let rec outputs = function
        | "-o" :: output :: rest -> Filename.dirname output :: outputs rest
        | _ :: rest -> outputs rest
        | [] -> []
      in
      let directories =
        List.filter_map
          (fun path ->
            let info = Cmt_format.read_cmt path in
            if outputs (Array.to_list info.cmt_args) <> [ requested ] then None
            else begin
              if info.cmt_builddir <> t.info.cmt_builddir then
                failwith "installed artifact: sibling build-directory conflict";
              match installed_origin ~caps path info with
              | Some (Installed sibling) when sibling.manifest_root = manifest_root ->
                  let digest =
                    Cap_stdlib.In_channel.with_open_bin ~caps sibling.source_path
                      (fun channel -> Digest.channel channel (-1))
                  in
                  if info.cmt_source_digest <> Some digest then
                    failwith
                      ("installed artifact: stale sibling source " ^ sibling.source_path);
                  Some sibling.directory
              | _ -> failwith "installed artifact: sibling owner conflict"
            end)
          annotations
        |> List.sort_uniq String.compare
      in
      match directories with
      | [] -> None
      | [ directory ] -> Some directory
      | _ -> failwith "installed artifact: ambiguous sibling object directory")

let read ~(caps : < Cap.fs_read ; .. >) path =
  ignore caps#fs_read;
  let info = Cmt_format.read_cmt path in
  let origin = Option.value (installed_origin ~caps path info) ~default:Build in
  let builddir =
    match origin with
    | Installed { directory; _ } -> directory
    | Build ->
        if
          info.cmt_builddir = "/workspace_root"
          || String.starts_with ~prefix:"/workspace_root/" info.cmt_builddir
        then
          match workspace ~caps path with
          | Some root ->
              let base = Filename.concat root "_build/default" in
              if
                not
                  (String.starts_with
                     ~prefix:(canonical ~caps base ^ "/")
                     (canonical ~caps path))
              then
                failwith
                  "annotation belongs to another source: no manifest ownership outside \
                   the build tree";
              if info.cmt_builddir = "/workspace_root" then base
              else
                Filename.concat base
                  (String.sub info.cmt_builddir 16 (String.length info.cmt_builddir - 16))
          | None -> failwith "cannot rebase /workspace_root: no dune-project found"
        else info.cmt_builddir
  in
  { path; info; builddir; origin }

let source t =
  match t.origin with
  | Installed { source_path; _ } -> source_path
  | Build -> (
      match t.info.cmt_sourcefile with
      | Some path ->
          if Filename.is_relative path then Filename.concat t.builddir path else path
      | None -> failwith "annotation has no source filename")

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

(* ^nlintcov-q6n2: inventory can regenerate volatile targets; the default gate
   rebuilds once after all queries, before consuming compiler evidence. *)
let rebuild_check ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) root =
  let command = "dune build @check --root " ^ Filename.quote root ^ " 2>&1" in
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
    failwith ("post-inventory @check rebuild failed: " ^ Buffer.contents buffer)

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
                          Some (resolve path, kind)
                      | _ -> None)
                    deps
              | _ -> failwith "Dune rule inventory has invalid dependencies"))
      | None | Some (Atom _) -> []
      | Some (List _) -> failwith "Dune rule inventory has an invalid context")

let inventory_cache = Hashtbl.create 8
let workspace_inputs = Hashtbl.create 8
let rule_inputs = Hashtbl.create 8

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
                        | Some (List [ Atom path ]) -> Some (resolve path, kind)
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
              let inputs =
                List.concat_map
                  (function
                    | List [ Atom "library"; fields ] -> modules Library fields
                    | List [ Atom "executables"; fields ] -> modules Executable fields
                    | _ -> [])
                  entries
              in
              Hashtbl.replace workspace_inputs root (List.map fst inputs);
              Some (List.map (fun (path, kind) -> (original path, kind)) inputs)
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
          let inputs = rule_modules ~caps root resolve in
          Hashtbl.replace rule_inputs root (List.map fst inputs);
          Some (List.map (fun (path, kind) -> (original path, kind)) inputs)
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
        let names = Array.to_list (Cap_sys.readdir ~caps dir) in
        let ignored = ignored ~caps ~directory:dir names in
        names
        |> List.concat_map (fun name ->
            let path = Filename.concat dir name in
            if name = "_build" || name = ".git" || List.mem name ignored then []
            else if Sys.is_directory path then
              (* ^nlintcov-q6n2: another project cannot classify this project's data. *)
              if Sys.file_exists (Filename.concat path "dune-project") then []
              else directories path
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

(* ^nlintcov-q6n2: source symlinks retain their declared module name. Canonicalising
   the final component would classify linked.ml by the unrelated target body.txt. *)
let declared_source ~caps input =
  let input = original (absolute ~caps input) in
  Filename.concat (canonical ~caps (Filename.dirname input)) (Filename.basename input)

let membership ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) input =
  let input = declared_source ~caps input in
  match workspace ~caps input with
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

type generated = { path : string; producer : string option }

(* ^nlintcov-q6n2: compilation declarations, not an annotation glob, are the second
   discovery channel. Missing outputs still reach main and fail typed evidence. *)
let generated_producer ~caps ~root source =
  let read_stanzas path =
    Cap_stdlib.In_channel.with_open_bin ~caps path (fun channel ->
        parse_rules (In_channel.input_all channel))
  in
  let target = Filename.basename source in
  let rec stanzas seen file =
    if List.mem file seen then None
    else
      read_stanzas file
      |> List.find_map (function
        | List [ Atom "include"; Atom included ] ->
            stanzas (file :: seen) (Filename.concat (Filename.dirname file) included)
        | List (Atom "rule" :: fields) ->
            let targets =
              List.concat_map
                (function
                  | List (Atom ("target" | "targets") :: targets) ->
                      List.filter_map
                        (function Atom name -> Some name | _ -> None)
                        targets
                  | _ -> [])
                fields
            in
            if List.mem target targets then
              Some ("rule (target " ^ target ^ ") in " ^ relative ~root file)
            else None
        | List (Atom ("copy_files" | "copy_files#") :: values) ->
            if
              List.exists
                (function
                  | Atom pattern when not (String.contains pattern '%') ->
                      Caps_policy.excluded [ Filename.basename pattern ] target
                  | _ -> false)
                values
            then Some ("copy_files stanza in " ^ relative ~root file ^ " for " ^ target)
            else None
        | _ -> None)
  in
  let inferred_interface file =
    if not (Filename.check_suffix source ".mli") then None
    else
      let name = Filename.remove_extension target in
      read_stanzas file
      |> List.find_map (function
        | List (Atom (("test" | "tests" | "executable" | "executables") as kind) :: fields)
          ->
            let names =
              List.concat_map
                (function
                  | List (Atom ("name" | "names") :: names) ->
                      List.filter_map
                        (function Atom name -> Some name | _ -> None)
                        names
                  | _ -> [])
                fields
            in
            if List.mem name names then
              Some
                ("Dune empty interface from " ^ kind ^ " (name " ^ name ^ ") in "
               ^ relative ~root file)
            else None
        | _ -> None)
  in
  let rec locate directory =
    let file = Filename.concat directory "dune" in
    if Sys.file_exists file then
      match stanzas [] file with
      | Some _ as found -> found
      | None -> inferred_interface file
    else if directory = root then None
    else
      let parent = Filename.dirname directory in
      if parent = directory then None else locate parent
  in
  try locate (Filename.dirname source)
  with Failure _ | Invalid_argument _ | Sys_error _ | Unix.Unix_error _ -> None

let generated_sources ~(caps : < Cap.fs_read ; Cap.fork ; Cap.exec ; .. >) ~root =
  let root = canonical ~caps root in
  let build = Filename.concat root "_build/default" in
  let producer = generated_producer ~caps ~root in
  match (inventory ~caps root, rule_inventory ~caps root) with
  | _, None -> Error "Dune generated-source inventory unavailable: describe rules @check"
  | None, _ -> Error "Dune generated-source inventory unavailable: describe workspace"
  | Some _, Some _ ->
      let inputs =
        Hashtbl.find workspace_inputs root @ Hashtbl.find rule_inputs root
        |> List.sort_uniq String.compare
      in
      (* Keep the actual PP input if no unpreprocessed input was declared. Dune
         emits some implicit executable interfaces directly as .pp.mli. *)
      let inputs =
        List.filter
          (fun path -> path = original path || not (List.mem (original path) inputs))
          inputs
      in
      Ok
        (inputs
        |> List.filter_map (fun path ->
            if
              (not (String.starts_with ~prefix:(build ^ "/") path))
              || not
                   (Filename.check_suffix path ".ml" || Filename.check_suffix path ".mli")
            then None
            else
              let source = Filename.concat root (relative ~root:build (original path)) in
              if
                Sys.file_exists source
                || project ~caps (Filename.dirname source) <> Some root
              then None
              else Some { path; producer = producer source }))

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
  let input = declared_source ~caps input in
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
          match workspace ~caps input with
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

(* ^nlintd-truth ^nlintcov-q6n2: truth follows authored inputs, including declared
   generated inputs; a build copy alone is not producer evidence. *)
let authored_source ~caps t =
  let built = original (source t) in
  match workspace ~caps built with
  | Some root when String.starts_with ~prefix:(root ^ "/_build/default/") built ->
      let checked_in =
        Filename.concat root (relative ~root:(root ^ "/_build/default") built)
      in
      if Sys.file_exists checked_in then checked_in
      else
        (* The annotation proves compilation. Reuse discovery's producer lookup
           without re-running volatile Dune inventories while checking evidence. *)
        begin match generated_producer ~caps ~root checked_in with
        | Some _ when Sys.file_exists built -> built
        | None -> failwith ("generated truth source producer unresolved: " ^ built)
        | _ -> failwith ("authored truth source unavailable: " ^ checked_in)
        end
  | _ -> built

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
    (* ^safe-y047: identical non-preprocessed bytes remain valid after checkout or
       cache restoration. Preprocessing still needs its separate source-time guard. *)
    if
      canonical ~caps built <> canonical ~caps annotated
      && (Unix.stat input).st_mtime > (Unix.stat t.path).st_mtime
    then failwith ("stale typed annotation: source is newer than annotation " ^ input)
  end;
  match t.info.cmt_annots with
  | Implementation _ when Filename.check_suffix input ".ml" -> ()
  | Interface _ when Filename.check_suffix input ".mli" -> ()
  | _ ->
      failwith
        "annotation is not a complete implementation/interface of the requested source"

(* ^nlintc-du4v: helper resolution shares the compiler evidence context. *)
let configured = ref None
let current () = !configured

let setup ~(caps : < Cap.fs_read ; .. >) t =
  ignore caps#fs_read;
  Envaux.reset_cache ~preserve_persistent_env:false;
  let resolve p =
    match t.origin with
    | Installed _ when p = "" -> Unavailable_original_cwd
    | Installed { own_objects; directory; _ } when p = own_objects ->
        Mapped_directory directory
    | Installed _
      when Filename.is_relative p || String.starts_with ~prefix:"/workspace_root" p -> (
        match installed_sibling ~caps t p with
        | Some directory -> Mapped_directory directory
        | None -> failwith ("installed artifact: unsupported relative dependency " ^ p))
    | Installed _ -> Mapped_directory p
    | Build ->
        Mapped_directory
          (if Filename.is_relative p then Filename.concat t.builddir p
           else if String.starts_with ~prefix:"/workspace_root/" p then
             Filename.concat t.builddir (String.sub p 16 (String.length p - 16))
           else p)
  in
  let rebase p =
    match resolve p with
    | Mapped_directory directory -> directory
    | Unavailable_original_cwd ->
        (* Preserve the unavailable slot, never the invocation cwd. Load_path has
           no empty-Dir constructor; a checked character device cannot contain CMIs.
           This representation is not an evidence mapping. *)
        let unavailable () =
          failwith
            "installed artifact: unavailable original cwd slot cannot be represented"
        in
        (try if (Unix.lstat "/dev/null").Unix.st_kind <> Unix.S_CHR then unavailable ()
         with Unix.Unix_error _ -> unavailable ());
        "/dev/null"
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
    match t.origin with
    | Installed _ -> []
    | Build ->
        List.map (fun (p : Clflags.visible_include) -> p.path) visible @ hidden
        |> List.concat_map (fun dir ->
            let installed = Filename.concat dir ".private" in
            let objects = Filename.dirname dir in
            let build =
              if
                Filename.basename dir = "public_cmi"
                && Filename.check_suffix objects ".objs"
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
          if not (Compilation_unit.Name.equal info.cmi_name unit_name) then
            failwith
              ("stale typed annotation: imported CMI fingerprint changed for " ^ name
             ^ " (wrong compilation unit at " ^ path ^ ")");
          match
            Array.find_opt
              (fun imported -> Import_info.has_name imported ~name:unit_name)
              info.cmi_crcs
          with
          | Some imported when Import_info.crc imported = Some expected -> ()
          | _ ->
              failwith
                ("stale typed annotation: imported CMI fingerprint changed for " ^ name)))
    t.info.cmt_imports;
  configured := Some t
