type t = { secret : string }

let redacted = "<redacted>"
let make secret = { secret }
let expose t = t.secret
let pp fmt _ = Format.pp_print_string fmt redacted
let to_string _ = redacted
let to_json _ = Eta_json.string redacted
