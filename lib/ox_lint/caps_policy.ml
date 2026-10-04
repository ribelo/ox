(* ^ncapslint-x3gi ^ncapslint-snhg: exclusions are policy data, with reasons. *)
let allowances =
  [
    ("lib/caps", "The Cap_* wrappers and token identity boundary contain the raw calls.");
    ( "lib/app/ox_app.ml",
      "The Door mints the powerbox, reads the environment and installs process signal \
       handlers." );
    ( "lib/ppx_yojson_minimal/main.ml",
      "Build-time preprocessor: reads source, writes stdout and exits; not a Door \
       program." );
    ( "lib/ox_lint",
      "Compiler build tool: reads sources and typed evidence, writes CLI output and \
       status; not a Door program." );
  ]

let read path =
  let ch = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ch)
    (fun () -> really_input_string ch (in_channel_length ch))

let self_check root =
  let path = Filename.concat root "docs/caps.md" in
  if not (Sys.file_exists path) then [ "caps allow-list: missing docs/caps.md" ]
  else
    let text = read path in
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
  List.exists (fun p -> p = "test" || p = "tests") parts
  || List.exists
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

(* ^ncapslint-nf4t: Dune's libraries boundary is independent of OCaml references.
   Read S-expressions, respecting quoted atoms, comments and nesting. *)
let dependencies path emit =
  let text = read path in
  let n = String.length text in
  let rec scan i line stack =
    if i < n then
      match text.[i] with
      | '\n' -> scan (i + 1) (line + 1) stack
      | ' ' | '\t' | '\r' -> scan (i + 1) line stack
      | ';' ->
          let stop = Option.value (String.index_from_opt text i '\n') ~default:n in
          scan stop line stack
      | '(' -> scan (i + 1) line (None :: stack)
      | ')' -> (
          match stack with
          | [] -> failwith ("malformed Dune file " ^ path)
          | _ :: rest -> scan (i + 1) line rest)
      | _ ->
          let quoted = text.[i] = '"' in
          let start = i + if quoted then 1 else 0 in
          let rec stop j =
            if j >= n then j
            else if quoted then
              if text.[j] = '\\' then stop (j + 2)
              else if text.[j] = '"' then j
              else stop (j + 1)
            else if List.mem text.[j] [ ' '; '\n'; '\t'; '\r'; '('; ')'; ';' ] then j
            else stop (j + 1)
          in
          let last = stop start in
          if quoted && last >= n then failwith ("unterminated Dune string " ^ path);
          let atom = String.sub text start (last - start) in
          if atom = "ox_caps.door" && List.mem (Some "libraries") stack then emit line;
          let stack = match stack with None :: rest -> Some atom :: rest | _ -> stack in
          scan (last + if quoted then 1 else 0) line stack
  in
  scan 0 1 []

let rec dune_files path =
  if Sys.is_directory path then
    Array.to_list (Sys.readdir path)
    |> List.sort String.compare
    |> List.concat_map (fun name ->
        if List.mem name [ "_build"; ".git"; "node_modules"; "_opam"; "test"; "tests" ]
        then []
        else dune_files (Filename.concat path name))
  else if Filename.basename path = "dune" then [ path ]
  else []

let check_dune paths emit =
  List.concat_map dune_files paths
  |> List.sort_uniq String.compare
  |> List.iter (fun path ->
      if
        not
          (List.mem (policy_path path)
             [ "lib/caps/dune"; "lib/app/dune"; "lib/test/dune" ])
      then dependencies path (fun line -> emit path line))
