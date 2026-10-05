(* ^nparse-gb03 ^safe-6ukl: byte counts and errors through the real public parse. *)
let with_limit input f =
  match Ox.Byte_limit.of_int input with
  | Ok value -> f value
  | Error `Invalid -> failwith "valid test bound refused"

let run () =
  let raw = "\"é\"" in
  if String.length raw <> 4 then failwith "UTF-8 fixture changed";
  with_limit 4 (fun max_bytes ->
      match Ox_json.parse ~max_bytes raw with
      | Ok (`String "é") -> ()
      | Error _ | Ok _ -> failwith "exact UTF-8 byte bound refused");
  with_limit 3 (fun max_bytes ->
      match Ox_json.parse ~max_bytes raw with
      | Error (`Too_large { limit = 3; length = 4 }) -> ()
      | Error _ | Ok _ -> failwith "UTF-8 bound did not count bytes");
  (match Ox_json.parse ~max_bytes:Ox.Byte_limit.zero "" with
  | Error (`Malformed _) -> ()
  | Error _ | Ok _ -> failwith "empty input fits zero but is malformed");
  (match Ox_json.parse ~max_bytes:Ox.Byte_limit.zero "{" with
  | Error (`Too_large { limit = 0; length = 1 }) -> ()
  | Error _ | Ok _ -> failwith "bound must precede malformed parsing");
  with_limit max_int (fun max_bytes ->
      match Ox_json.parse ~max_bytes "{}" with
      | Ok (`Assoc []) -> ()
      | Error _ | Ok _ -> failwith "max_int must be a valid byte limit");
  let malformed = "{\n  \"a\": }" in
  let original =
    try
      match Yojson.Safe.from_string malformed with
      | _ -> failwith "malformed fixture parsed"
    with Yojson.Json_error message -> message
  in
  with_limit (String.length malformed) (fun max_bytes ->
      match Ox_json.parse ~max_bytes malformed with
      | Error (`Malformed message) when String.equal original message -> ()
      | Error _ | Ok _ -> failwith "Yojson wire message or offsets changed");
  match Ox.Byte_limit.of_int (-1) with
  | Error `Invalid -> ()
  | Ok _ -> failwith "negative input reached a parse-callable bound"
