open Eta_schema

type error = [ `Config of string ]
let ( let* ) = Result.bind
let issue_text issues =
  String.concat "; " (List.map (fun issue ->
    let pointer = Eta_schema.issue_to_json_pointer issue in
    let text = Eta_schema.render_issue issue in
    if pointer = "" then text else text ^ " (" ^ pointer ^ ")") issues)
let fail path message = Error [ Eta_schema.issue ~path message ]
let path ~name ~config ~getenv = match config with
  | Some file -> file
  | None ->
      let base = match getenv "XDG_CONFIG_HOME" with
        | Some value when value <> "" -> value
        | _ -> (match getenv "HOME" with Some home -> Filename.concat home ".config" | None -> ".config") in
      Filename.concat (Filename.concat base name) "config.toml"

let rec value path (v : Toml.Types.value) =
  match v with
  | TBool b -> Ok (Json.bool b)
  | TInt n -> Ok (Json.int n)
  | TFloat n -> Result.map_error (fun issues -> List.map (fun issue -> { issue with path }) issues) (Json.number n)
  | TString s -> Result.map_error (fun issues -> List.map (fun issue -> { issue with path }) issues) (Json.string s)
  | TDate _ -> fail path "TOML dates have no JSON representation"
  | TArray a ->
      let vs = match a with
        | NodeEmpty -> [] | NodeBool xs -> List.map (fun x -> Toml.Types.TBool x) xs
        | NodeInt xs -> List.map (fun x -> Toml.Types.TInt x) xs
        | NodeFloat xs -> List.map (fun x -> Toml.Types.TFloat x) xs
        | NodeString xs -> List.map (fun x -> Toml.Types.TString x) xs
        | NodeDate xs -> List.map (fun x -> Toml.Types.TDate x) xs
        | NodeArray xs -> List.map (fun x -> Toml.Types.TArray x) xs
        | NodeTable xs -> List.map (fun x -> Toml.Types.TTable x) xs in
      let rec loop i acc = function
        | [] -> Ok (Json.array (List.rev acc))
        | h :: t -> let* j = value (path @ [Index i]) h in loop (i+1) (j::acc) t in
      loop 0 [] vs
  | TTable table -> table_json path table
and table_json path table =
  let rec loop acc = function
    | [] -> Result.map_error (fun issues -> List.map (fun issue -> { issue with path }) issues) (Json.object_ (List.rev acc))
    | (key,v)::tail ->
        let name = Toml.Types.Table.Key.to_string key in
        let* j = value (path @ [Field name]) v in
        loop ((name,j)::acc) tail in
  loop [] (Toml.Types.Table.bindings table)

let segments pointer =
  let decode s =
    let b = Buffer.create (String.length s) in
    let rec go i = if i < String.length s then
      if s.[i] = '~' && i + 1 < String.length s then
        (Buffer.add_char b (if s.[i+1] = '1' then '/' else '~'); go (i+2))
      else (Buffer.add_char b s.[i]; go (i+1)) in
    go 0; Buffer.contents b in
  match String.split_on_char '/' pointer with _ :: xs -> List.map decode xs | [] -> []

let rec put doc keys replacement = match keys,doc with
  | [], _ -> replacement
  | key::rest, Json.Object fields ->
      let seen = List.mem_assoc key fields in
      let fields = List.map (fun (name,v) -> if name = key then (name,put v rest replacement) else (name,v)) fields in
      let fields = if seen then fields else fields @ [key,put ((Json.object_ [] |> Result.get_ok)) rest replacement] in
      Json.object_ fields |> Result.get_ok
  | key::rest, _ -> put ((Json.object_ [] |> Result.get_ok)) (key::rest) replacement

let rec unknown schema doc path =
  match schema,doc with
  | Json.Object meta, Json.Object fields ->
      (match List.assoc_opt "properties" meta with
       | Some (Json.Object props) ->
           let rec check = function
             | [] -> Ok ()
             | (name,v)::tail ->
               let* () = match List.assoc_opt name props with
                 | Some sub -> unknown sub v (path @ [Field name])
                 | None -> (match List.assoc_opt "additionalProperties" meta with
                   | Some (Json.Bool true) -> Ok ()
                   | _ -> fail (path @ [Field name]) "unknown key") in
               check tail in
           check fields
       | _ -> Ok ())
  | Json.Object meta, Json.Array xs ->
      (match List.assoc_opt "items" meta with
       | Some item ->
           let rec check i = function [] -> Ok () | h::t -> let* () = unknown item h (path @ [Index i]) in check (i+1) t in
           check 0 xs
       | None -> Ok ())
  | _ -> Ok ()

let rec property_type schema = function
  | [] -> (match schema with
      | Json.Object fields -> List.assoc_opt "type" fields
      | _ -> None)
  | key :: tail -> (match schema with
      | Json.Object fields ->
          (match List.assoc_opt "properties" fields with
           | Some (Json.Object properties) ->
               (match List.assoc_opt key properties with
                | Some child -> property_type child tail
                | None -> None)
           | _ -> None)
      | _ -> None)

let override_value schema mark raw =
  let path = List.map (fun key -> Field key) (segments mark.Eta_schema.pointer) in
  let error message = Error (`Config (issue_text [ Eta_schema.issue ~path message ])) in
  match property_type schema (segments mark.pointer) with
  | Some (Json.String "string") | None ->
      Result.map_error (fun issues -> `Config (issue_text issues)) (Json.string raw)
  | _ -> (match Toml.Parser.from_string ("value = " ^ raw) with
      | `Error _ -> error ("invalid environment value for " ^ mark.pointer)
      | `Ok table -> (match Toml.Types.Table.find_opt
            (Toml.Types.Table.Key.of_string "value") table with
          | None -> error ("invalid environment value for " ^ mark.pointer)
          | Some v -> Result.map_error (fun issues -> `Config (issue_text issues)) (value path v)))

let decode ~schema ~getenv text =
  let* parsed = match Toml.Parser.from_string text with
    | `Ok table -> (match table_json [] table with
      | Ok j -> Ok j | Error issues -> Error (`Config (issue_text issues)))
    | `Error (message, location) -> Error (`Config (Printf.sprintf "TOML line %d, column %d: %s" location.line location.column message)) in
  let* parsed =
    let rec apply current = function
      | [] -> Ok current
      | mark::tail ->
          (match mark.Eta_schema.env with
           | None -> apply current tail
           | Some key -> match getenv key with
             | None -> apply current tail
             | Some raw ->
                let* v = override_value (Eta_schema.json_schema schema) mark raw in
                apply (put current (segments mark.pointer) v) tail) in
    apply parsed (Eta_schema.field_marks schema) in
  let* () = match unknown (Eta_schema.json_schema schema) parsed [] with
    | Ok () -> Ok () | Error issues -> Error (`Config (issue_text issues)) in
  match Eta_schema.decode_result schema parsed with
  | Ok result -> Ok result
  | Error issues -> Error (`Config (issue_text issues))

let load ~schema ~getenv ~read ~path =
  match read path with
  | Error msg -> Error (`Config (Printf.sprintf "%s: %s" path msg))
  | Ok text -> decode ~schema ~getenv text
