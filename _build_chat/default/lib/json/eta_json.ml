type t = Yojson.Safe.t

(* The two ways a byte-bounded parse can fail. Kept as a polymorphic variant so
   a caller that only handles the bound narrows the union by matching. The bound
   refusal carries its own record because polymorphic variants hold no inline
   records. *)
type too_large = { limit : int; length : int }
type parse_error = [ `Malformed of string | `Too_large of too_large ]

let parse ?max_bytes raw =
  (match max_bytes with
  | Some limit when limit < 0 ->
      invalid_arg "Eta_json.parse: max_bytes must not be negative"
  | Some _ | None -> ());
  match max_bytes with
  | Some limit when String.length raw > limit ->
      Error (`Too_large { limit; length = String.length raw })
  | Some _ | None -> (
      try Ok (Yojson.Safe.from_string raw)
      with Yojson.Json_error message -> Error (`Malformed message))

let to_string json = Yojson.Safe.to_string json
let compact = to_string

let pp_parse_error fmt = function
  | `Malformed message -> Format.pp_print_string fmt message
  | `Too_large { limit; length } ->
      Format.fprintf fmt "JSON input of %d bytes exceeds max_bytes (%d)" length limit

type issue = { path : string; message : string; got : t }

(* The deriver's rendering of a failure: the offending subtree, compacted and bounded, so
   one log line cannot grow with the document. *)
let truncate json =
  let text = to_string json in
  if String.length text > 200 then String.sub text 0 200 ^ "..." else text

let pp_issue fmt { path; message; got } =
  let text = Printf.sprintf "%s, got %s" message (truncate got) in
  if path = "" then Format.pp_print_string fmt text
  else Format.fprintf fmt "%s: %s" path text

let string value = `String value
let bool value = `Bool value
let int value = `Int value

let float value =
  if classify_float value = FP_nan || classify_float value = FP_infinite then None
  else Some (`Float value)

let array values = `List values
let array_map f values = array (List.map f values)

let object_ fields =
  let rec loop acc = function
    | [] -> `Assoc (List.rev acc)
    | (_, None) :: rest -> loop acc rest
    | (name, Some value) :: rest -> loop ((name, value) :: acc) rest
  in
  loop [] fields

let member name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let string_member name json =
  match member name json with Some (`String value) -> Some value | _ -> None

let scalar_string_member name json =
  match member name json with
  | Some (`String value) -> Some value
  | Some (`Int value) -> Some (string_of_int value)
  | Some (`Intlit value) -> Some value
  | Some (`Float value) -> Some (Printf.sprintf "%.17g" value)
  | Some (`Bool value) -> Some (string_of_bool value)
  | _ -> None

let int_member name json =
  match member name json with
  | Some (`Int value) -> Some value
  | Some (`Intlit value) -> int_of_string_opt value
  | Some (`Float value) when Float.is_integer value ->
      let int_value = int_of_float value in
      if Float.equal (float_of_int int_value) value then Some int_value else None
  | Some (`Float _) -> None
  | _ -> None

let array_member name json =
  match member name json with Some (`List values) -> Some values | _ -> None

let object_member name json =
  match member name json with Some (`Assoc _ as value) -> Some value | _ -> None

(* ---------- Of_json: decoder combinators (^nderive-vq4n) ---------- *)

module Of_json = struct
  type 'a t = Yojson.Safe.t -> ('a, issue) result

  (* The failure is data: what was expected, and the value that did not fit. Rendering it
     is [pp_issue]'s job, so a decoder stays portable and a discarded attempt
     ([one_of], [try_or_none]) costs no string. *)
  let fail expected json =
    Error { path = ""; message = "expected " ^ expected; got = json }

  (* A decoder reports its issue relative to the value it was handed, so a builder prefixes
     the path it adds; [""] is the value itself. Segments join the way the deriver joins
     them: a field by name, a list by its index in brackets, both after a dot, so
     [field "args" (field "index" int)] reports [args.index] and a list element inside it
     reports [args.ids.[1]]. *)
  let under prefix path = if path = "" then prefix else prefix ^ "." ^ path
  let string = function `String value -> Ok value | json -> fail "string" json
  let bool = function `Bool value -> Ok value | json -> fail "bool" json

  let int = function
    | `Int value -> Ok value
    | `Intlit text as json -> (
        match int_of_string_opt text with
        | Some value -> Ok value
        | None -> fail "int" json)
    | json -> fail "int" json

  let float = function
    | `Float value -> Ok value
    | `Int value -> Ok (float_of_int value)
    | json -> fail "number" json

  let null = function `Null -> Ok () | json -> fail "null" json

  let list decoder json =
    match json with
    | `List items ->
        let rec loop index acc = function
          | [] -> Ok (List.rev acc)
          | item :: rest -> (
              match decoder item with
              | Ok value -> loop (index + 1) (value :: acc) rest
              | Error issue ->
                  Error
                    {
                      issue with
                      path = under ("[" ^ string_of_int index ^ "]") issue.path;
                    })
        in
        loop 0 [] items
    | json -> fail "array" json

  let option decoder = function
    | `Null -> Ok None
    | json -> (
        match decoder json with Ok value -> Ok (Some value) | Error issue -> Error issue)

  let field name decoder json =
    match json with
    | `Assoc members -> (
        match List.assoc_opt name members with
        | None -> Error { path = ""; message = "missing field " ^ name; got = json }
        | Some value -> (
            match decoder value with
            | Ok value -> Ok value
            | Error issue -> Error { issue with path = under name issue.path }))
    | json -> fail "object" json

  let at names decoder json =
    List.fold_right (fun name decoder -> field name decoder) names decoder json

  let one_of alternatives json =
    let rec loop = function
      | [] -> fail "one of the alternatives" json
      | decoder :: rest -> (
          match decoder json with Ok value -> Ok value | Error _ -> loop rest)
    in
    loop alternatives

  let try_or_none decoder json =
    match decoder json with Ok value -> Ok (Some value) | Error _ -> Ok None
end
