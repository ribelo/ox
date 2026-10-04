(* ^ncapslint-x3gi ^ncapslint-snhg: the shipped allow-list is empty. *)
let allowances = []

let read ~caps path =
  Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps path In_channel.input_all

let self_check ~caps root =
  let path = Filename.concat root "docs/caps.md" in
  if not (Sys.file_exists path) then [ "caps allow-list: missing docs/caps.md" ]
  else
    let text = read ~caps path in
    let expected =
      List.map
        (fun (glob, reason) ->
          Printf.sprintf "| %c%s%c | %s |" (Char.chr 96) glob (Char.chr 96) reason)
        allowances
    in
    let active = ref false in
    let rows =
      String.split_on_char '\n' text
      |> List.filter (fun line ->
          if line = "<!-- caps-allowances -->" then (
            active := true;
            false)
          else if line = "<!-- /caps-allowances -->" then (
            active := false;
            false)
          else !active && String.starts_with ~prefix:"| \x60" line)
    in
    List.filter_map
      (fun row ->
        if List.mem row rows then None
        else Some ("caps allow-list: undocumented entry or reason " ^ row))
      expected
    @ List.filter_map
        (fun row ->
          if List.mem row expected then None
          else Some ("caps allow-list: unexpected documented entry " ^ row))
        rows
    @ List.filter_map
        (fun row ->
          if List.length (List.filter (( = ) row) rows) > 1 then
            Some ("caps allow-list: duplicate documented entry " ^ row)
          else None)
        (List.sort_uniq String.compare rows)

(* Gitignore-style path globs: directory patterns include their descendants;
   basename patterns match at any depth; * does not cross /, ** does. *)
let glob pattern path =
  let n, m = (String.length pattern, String.length path) in
  let memo = Hashtbl.create 32 in
  let rec match_ i j =
    match Hashtbl.find_opt memo (i, j) with
    | Some b -> b
    | None ->
        let b =
          if i = n then j = m
          else
            match pattern.[i] with
            | '*' ->
                let double = i + 1 < n && pattern.[i + 1] = '*' in
                let next = i + if double then 2 else 1 in
                match_ next j
                || (double && next < n && pattern.[next] = '/' && match_ (next + 1) j)
                || (j < m && (double || path.[j] <> '/') && match_ i (j + 1))
            | '?' -> j < m && path.[j] <> '/' && match_ (i + 1) (j + 1)
            | '[' -> (
                match String.index_from_opt pattern (i + 1) ']' with
                | None -> j < m && path.[j] = '[' && match_ (i + 1) (j + 1)
                | Some stop ->
                    let negative =
                      i + 1 < stop && (pattern.[i + 1] = '!' || pattern.[i + 1] = '^')
                    in
                    let rec member k =
                      k < stop
                      &&
                      if k + 2 < stop && pattern.[k + 1] = '-' then
                        (path.[j] >= pattern.[k] && path.[j] <= pattern.[k + 2])
                        || member (k + 3)
                      else path.[j] = pattern.[k] || member (k + 1)
                    in
                    j < m
                    && path.[j] <> '/'
                    && member (i + if negative then 2 else 1) <> negative
                    && match_ (stop + 1) (j + 1))
            | _ -> j < m && pattern.[i] = path.[j] && match_ (i + 1) (j + 1)
        in
        Hashtbl.add memo (i, j) b;
        b
  in
  match_ 0 0

(* Compare policy boundaries relative to the invocation root, independent of
   absolute/dot-qualified spelling; lexical parent segments cannot widen a boundary. *)
let policy_path path =
  let absolute =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  let parts =
    String.split_on_char '/' absolute
    |> List.fold_left
         (fun parts -> function
           | "" | "." -> parts
           | ".." -> ( match parts with _ :: rest -> rest | [] -> [])
           | part -> part :: parts)
         []
  in
  let absolute = "/" ^ String.concat "/" (List.rev parts) in
  let root = Sys.getcwd () ^ "/" in
  if String.starts_with ~prefix:root absolute then
    String.sub absolute (String.length root) (String.length absolute - String.length root)
  else absolute

let excluded allows path =
  let path = policy_path path in
  let parts = String.split_on_char '/' path in
  List.exists
    (fun pattern ->
      let pattern =
        if String.starts_with ~prefix:"/" pattern then
          String.sub pattern 1 (String.length pattern - 1)
        else pattern
      in
      let pattern =
        if String.ends_with ~suffix:"/" pattern then
          String.sub pattern 0 (String.length pattern - 1)
        else pattern
      in
      let prefixes =
        let rec go prefix = function
          | [] -> []
          | x :: xs ->
              let prefix = if prefix = "" then x else prefix ^ "/" ^ x in
              prefix :: go prefix xs
        in
        go "" parts
      in
      List.exists (glob pattern) prefixes
      || ((not (String.contains pattern '/')) && List.exists (glob pattern) parts))
    allows

(* A direct library dependency grants minting to that stanza's modules. *)
type sexp = Atom of string | List of sexp list

let sexps text =
  let n = String.length text in
  let rec space i =
    if i >= n then i
    else
      match text.[i] with
      | ' ' | '\n' | '\r' | '\t' -> space (i + 1)
      | ';' -> space (Option.value (String.index_from_opt text i '\n') ~default:n)
      | _ -> i
  in
  let rec items closing i acc =
    let i = space i in
    if i = n then
      if closing then failwith "unterminated Dune stanza" else (List.rev acc, i)
    else if text.[i] = ')' then
      if closing then (List.rev acc, i + 1) else failwith "unexpected Dune close"
    else if text.[i] = '(' then
      let nested, next = items true (i + 1) [] in
      items closing next (List nested :: acc)
    else
      let quoted = text.[i] = '"' in
      let start = i + if quoted then 1 else 0 in
      let buf = Buffer.create 16 in
      let rec atom j =
        if j >= n then if quoted then failwith "unterminated Dune string" else j
        else if quoted && text.[j] = '"' then j + 1
        else if quoted && text.[j] = '\\' then begin
          if j + 1 >= n then failwith "unterminated Dune escape";
          Buffer.add_char buf text.[j + 1];
          atom (j + 2)
        end
        else if (not quoted) && List.mem text.[j] [ ' '; '\n'; '\r'; '\t'; '('; ')'; ';' ]
        then j
        else (
          Buffer.add_char buf text.[j];
          atom (j + 1))
      in
      let next = atom start in
      items closing next (Atom (Buffer.contents buf) :: acc)
  in
  fst (items false 0 [])

let field name fields =
  List.find_map
    (function List (Atom key :: values) when key = name -> Some values | _ -> None)
    fields

let owns module_ fields =
  match field "modules" fields with
  | None -> true
  | Some values ->
      let rec atoms = function
        | Atom value -> [ String.lowercase_ascii value ]
        | List values -> List.concat_map atoms values
      in
      let names = List.concat_map atoms values in
      let rec split before = function
        | "\\" :: rest -> (List.rev before, rest)
        | name :: rest -> split (name :: before) rest
        | [] -> (List.rev before, [])
      in
      let included, excluded = split [] names in
      (List.mem ":standard" included || List.mem module_ included)
      && not (List.mem module_ excluded)

let declared_boundary ~caps source grants =
  let directory = Filename.dirname source in
  let module_ =
    String.lowercase_ascii (Filename.remove_extension (Filename.basename source))
  in
  let rec locate dir =
    let dune = Filename.concat dir "dune" in
    if Sys.file_exists dune && not (Sys.is_directory dune) then begin
      let stanzas = sexps (read ~caps dune) in
      let subdirs =
        List.exists
          (function
            | List [ Atom "include_subdirs"; Atom ("qualified" | "unqualified") ] -> true
            | _ -> false)
          stanzas
      in
      (dir = directory || subdirs)
      && List.exists
           (function
             | List
                 (Atom ("library" | "executable" | "executables" | "test" | "tests")
                 :: fields) ->
                 owns module_ fields && grants module_ fields
             | _ -> false)
           stanzas
    end
    else if Sys.file_exists (Filename.concat dir "dune-project") then false
    else
      let parent = Filename.dirname dir in
      parent <> dir && locate parent
  in
  locate directory

let declares_door ~caps source =
  declared_boundary ~caps source (fun _ fields ->
      match field "libraries" fields with
      | Some libraries -> List.mem (Atom "ox_caps.door") libraries
      | None -> false)

let declares_test ~caps source =
  declared_boundary ~caps source (fun _ fields ->
      match field "libraries" fields with
      | Some libraries -> List.mem (Atom "ox_test") libraries
      | None -> false)

let private_module ~caps source =
  declared_boundary ~caps source (fun module_ fields ->
      match field "private_modules" fields with
      | Some modules -> owns module_ [ List (Atom "modules" :: modules) ]
      | None -> false)

let check_dune ~caps:_ _paths _emit = ()
