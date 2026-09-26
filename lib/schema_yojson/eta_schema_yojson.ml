type external_json = Yojson.Safe.t

(* Conversion attaches the input location as it descends: array elements prepend
   their zero-based index and object fields prepend their stored name, so the
   issue path reads outermost-to-innermost. Field names stay unescaped here;
   [Eta_schema.issue_to_json_pointer] escapes them when rendering. Checked
   [Eta_schema.Json] construction reports object-name issues with their own
   relative [Field] path, which this descent then prefixes. *)
let rec of_yojson = function
  | `Null -> Ok Eta_schema.Json.null
  | `Bool value -> Ok (Eta_schema.Json.bool value)
  | `Int value -> Ok (Eta_schema.Json.int value)
  | `Intlit value -> Eta_schema.Json.intlit value
  | `Float value -> Eta_schema.Json.number value
  | `String value -> Eta_schema.Json.string value
  | `List values -> array_values 0 [] values
  | `Assoc fields -> object_fields [] fields
  | `Tuple _ | `Variant _ ->
      Error [ Eta_schema.issue "unsupported non-standard JSON value" ]

and array_values index reversed = function
  | [] -> Ok (Eta_schema.Json.array (List.rev reversed))
  | value :: rest -> (
      match of_yojson value with
      | Ok value -> array_values (index + 1) (value :: reversed) rest
      | Error issues -> Error (Eta_schema.at_index index issues))

and object_fields reversed = function
  | [] -> Eta_schema.Json.object_ (List.rev reversed)
  | (name, value) :: rest -> (
      match of_yojson value with
      | Ok value -> object_fields ((name, value) :: reversed) rest
      | Error issues -> Error (Eta_schema.at_field name issues))

let rec to_yojson = function
  | Eta_schema.Json.Null -> `Null
  | Bool value -> `Bool value
  | Number (Int value) -> `Int value
  | Number (Intlit value) -> `Intlit value
  | Number (Float value) -> `Float value
  | String value -> `String value
  | Array values -> `List (List.map to_yojson values)
  | Object fields ->
      `Assoc (List.map (fun (name, value) -> (name, to_yojson value)) fields)

include Eta_schema.Make (struct
  type nonrec external_json = external_json

  let of_external = of_yojson
  let to_external = to_yojson
end)
