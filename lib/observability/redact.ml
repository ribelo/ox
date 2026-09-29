type t = { secret : string }

let redacted = "<redacted>"
let make secret = { secret }
let expose t = t.secret
let pp fmt _ = Format.pp_print_string fmt redacted
let to_string _ = redacted
let to_json _ = Ox_json.string redacted
let yojson_of_t _ = `String redacted

let t_of_yojson = function
  | `String text -> Ok { secret = text }
  | json -> Error ("redacted: expected string, got " ^ Yojson.Safe.to_string json)
