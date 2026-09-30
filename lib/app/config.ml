type error = [ `Config of string ]
type validation_error = { pointer : string; message : string }

type 'cfg t = {
  of_yojson : Yojson.Safe.t -> ('cfg, string) result;
  yojson_of_t : 'cfg -> Yojson.Safe.t;
  env : getenv:(string -> string option) -> 'cfg -> 'cfg;
}

let none =
  {
    of_yojson = (fun _ -> Ok ());
    yojson_of_t = (fun () -> `Assoc []);
    env = (fun ~getenv:_ () -> ());
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

(* ^napp-9x0s: why a read failed, which is exactly the difference the Door's rule turns
   on. An absent file at the Door's own default path is the empty document; a file that is
   there and cannot be read is an error at either path. *)
type read_error = [ `Missing | `Unreadable of string ]

(* ^napp-9x0s: where the text comes from. Only the Door's own default path for [name] may
   be absent; a path the operator named with --config must exist. *)
type missing = [ `Defaults | `Required ]
type source = [ `Default of string | `Explicit of string ]

let default_path ~name ~file_name ~getenv =
  let base =
    match getenv "XDG_CONFIG_HOME" with
    | Some value when value <> "" -> value
    | _ -> (
        match getenv "HOME" with
        | Some home -> Filename.concat home ".config"
        | None -> ".config")
  in
  Filename.concat (Filename.concat base name) file_name

let path_with ~file_name ~name ~config ~getenv =
  match config with Some file -> file | None -> default_path ~name ~file_name ~getenv

let resolve_with ~file_name ~name ~config ~getenv =
  match config with
  | Some file -> `Explicit file
  | None -> `Default (default_path ~name ~file_name ~getenv)

let path ~name ~config ~getenv = path_with ~file_name:"config.toml" ~name ~config ~getenv

let resolve ~name ~config ~getenv =
  resolve_with ~file_name:"config.toml" ~name ~config ~getenv

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

let decode_with ~of_yojson ~spec ~getenv text =
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
    match of_yojson parsed with
    | Ok settings -> Ok settings
    | Error message -> Error (`Config message)
  in
  Ok (spec.env ~getenv settings)

(* ^napp-9x0s: an absent file is the empty document only where the Door chose the path.
   A config type whose fields all carry defaults then starts a fresh install with no file;
   an absent --config path, and a file that is there and cannot be read at either path,
   stay errors naming the path. *)
let load_decoding ~of_yojson ~missing ~spec ~getenv ~read ~(source : source) =
  let path = match source with `Explicit path | `Default path -> path in
  match read path with
  | Ok text -> decode_with ~of_yojson ~spec ~getenv text
  | Error (`Unreadable message) -> Error (`Config (Printf.sprintf "%s: %s" path message))
  | Error `Missing -> (
      match source with
      | `Default _ when missing = `Defaults -> decode_with ~of_yojson ~spec ~getenv ""
      | `Default _ -> Error (`Config (Printf.sprintf "%s: no such file" path))
      | `Explicit _ -> Error (`Config (Printf.sprintf "%s: no such file" path)))

(* ^napp-ersz: reject non-regular paths before opening (FIFO opens can block),
   then verify the opened descriptor as well. Buf_read caps allocation even when
   a regular file grows after opening. *)
let read_regular ~max_bytes path =
  if max_bytes < 0 || max_bytes = max_int then
    invalid_arg "Config.read_regular: max_bytes";
  try
    if (Eio.Path.stat ~follow:true path).kind <> `Regular_file then
      Error (`Unreadable "not a regular file")
    else
      Eio.Path.with_open_in path (fun flow ->
          if (Eio.File.stat flow).kind <> `Regular_file then
            Error (`Unreadable "not a regular file")
          else
            match
              Eio.Buf_read.parse ~max_size:(max_bytes + 1) Eio.Buf_read.take_all flow
            with
            | Ok text when String.length text <= max_bytes -> Ok text
            | Ok _ | Error _ -> Error (`Unreadable "file exceeds byte limit"))
  with
  | Eio.Io (Eio.Fs.E (Eio.Fs.Not_found _), _) -> Error `Missing
  | Eio.Io _ as exn -> Error (`Unreadable (Printexc.to_string exn))

let decode ~spec ~getenv text = decode_with ~of_yojson:spec.of_yojson ~spec ~getenv text

let load_with ~missing ~spec ~getenv ~read ~source =
  load_decoding ~of_yojson:spec.of_yojson ~missing ~spec ~getenv ~read ~source

let load ~spec ~getenv ~read ~source =
  load_with ~missing:`Defaults ~spec ~getenv ~read ~source
