type error = [ `Config of string ]
type validation_error = { pointer : string; message : string }

type 'cfg t = {
  of_yojson : Yojson.Safe.t -> ('cfg, string) result;
  yojson_of_t : 'cfg -> Yojson.Safe.t;
  env : getenv:(string -> string option) -> 'cfg -> 'cfg;
}

let ( let* ) = Result.bind
let pointer_text pointer text = if pointer = "" then text else text ^ " (" ^ pointer ^ ")"

let render_validation_errors errors =
  String.concat "; "
    (List.map (fun { pointer; message } -> pointer_text pointer message) errors)

(* JSON pointers for the two refusals the TOML-to-JSON step makes itself (RFC 6901
   escaping). The deriver's messages carry their own dotted path instead. *)
type step = Field of string | Index of int

let escape_segment segment =
  let buffer = Buffer.create (String.length segment) in
  String.iter
    (fun char ->
      match char with
      | '~' -> Buffer.add_string buffer "~0"
      | '/' -> Buffer.add_string buffer "~1"
      | char -> Buffer.add_char buffer char)
    segment;
  Buffer.contents buffer

let json_pointer steps =
  match steps with
  | [] -> ""
  | steps ->
      "/"
      ^ String.concat "/"
          (List.map
             (function
               | Field name -> escape_segment name | Index index -> string_of_int index)
             steps)

let refuse path message = Error (`Config (pointer_text (json_pointer path) message))

let path ~name ~config ~getenv =
  match config with
  | Some file -> file
  | None ->
      let base =
        match getenv "XDG_CONFIG_HOME" with
        | Some value when value <> "" -> value
        | _ -> (
            match getenv "HOME" with
            | Some home -> Filename.concat home ".config"
            | None -> ".config")
      in
      Filename.concat (Filename.concat base name) "config.toml"

(* Story ^nnoschema-boxo: the config file format is unchanged. TOML is parsed and
   converted to Yojson.Safe.t here; the consumer's derived decoder takes over from
   there, so nothing in this file knows a field name. *)
let rec value path (v : Toml.Types.value) : (Yojson.Safe.t, error) result =
  match v with
  | TBool b -> Ok (`Bool b)
  | TInt n -> Ok (`Int n)
  | TFloat n ->
      if Float.is_finite n then Ok (`Float n)
      else refuse path "TOML floats must be finite"
  | TString s -> Ok (`String s)
  | TDate _ -> refuse path "TOML dates have no JSON representation"
  | TArray a ->
      let vs =
        match a with
        | NodeEmpty -> []
        | NodeBool xs -> List.map (fun x -> Toml.Types.TBool x) xs
        | NodeInt xs -> List.map (fun x -> Toml.Types.TInt x) xs
        | NodeFloat xs -> List.map (fun x -> Toml.Types.TFloat x) xs
        | NodeString xs -> List.map (fun x -> Toml.Types.TString x) xs
        | NodeDate xs -> List.map (fun x -> Toml.Types.TDate x) xs
        | NodeArray xs -> List.map (fun x -> Toml.Types.TArray x) xs
        | NodeTable xs -> List.map (fun x -> Toml.Types.TTable x) xs
      in
      let rec loop i acc = function
        | [] -> Ok (`List (List.rev acc))
        | h :: t ->
            let* json = value (path @ [ Index i ]) h in
            loop (i + 1) (json :: acc) t
      in
      loop 0 [] vs
  | TTable table -> table_json path table

and table_json path table =
  let rec loop acc = function
    | [] -> Ok (`Assoc (List.rev acc))
    | (key, v) :: tail ->
        let name = Toml.Types.Table.Key.to_string key in
        let* json = value (path @ [ Field name ]) v in
        loop ((name, json) :: acc) tail
  in
  loop [] (Toml.Types.Table.bindings table)

let decode ~spec ~getenv text =
  let* parsed =
    match Toml.Parser.from_string text with
    | `Ok table -> table_json [] table
    | `Error (message, location) ->
        Error
          (`Config
             (Printf.sprintf "TOML line %d, column %d: %s" location.line location.column
                message))
  in
  let* settings =
    match spec.of_yojson parsed with
    | Ok settings -> Ok settings
    | Error message -> Error (`Config message)
  in
  Ok (spec.env ~getenv settings)

let load ~spec ~getenv ~read ~path =
  match read path with
  | Error msg -> Error (`Config (Printf.sprintf "%s: %s" path msg))
  | Ok text -> decode ~spec ~getenv text
