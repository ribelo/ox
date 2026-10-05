(* Unit tests for the ox_json package.

   ^njson-7pjx: the public module exports the helpers v1 established
   (^njson-3ph9): a byte-bounded parse, [to_string] and [compact], the scalar
   constructors, [object_] and [array], and the [_member] accessors. Every
   accessor is checked on a present member, a missing member, and a
   wrong-typed member.

   ^njson-nc66: [parse] refuses input over a byte bound with a typed error that
   names the bound and the length, and malformed text with a different error,
   so a peer cannot make the caller allocate unboundedly and the caller can
   still tell the two refusals apart without matching on message text.

   The protocol group is the Leash request as a derived type (^nnoschema-44wj,
   ^nnoschema-zi2m) beside a CDP-shaped document that stays unchecked through
   Ox_json (^njson-cdp0): shapes we own derive their codec, shapes a peer owns
   do not. The of_json group (^nderive-vq4n) reads that peer-shaped JSON by composing
   decoders. *)

(* ^njson-7pjx: the value type is [Yojson.Safe.t] itself, not a copy. *)
let (_ : Ox_json.t -> Yojson.Safe.t) = fun value -> value
let (_ : Yojson.Safe.t -> Ox_json.t) = fun value -> value

let json =
  Alcotest.testable
    (fun ppf value -> Format.pp_print_string ppf (Ox_json.to_string value))
    (fun left right -> String.equal (Ox_json.to_string left) (Ox_json.to_string right))

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      Alcotest.failf "%s: unexpected error %a" label Ox_json.pp_parse_error error

let expect_error label = function
  | Ok _ -> Alcotest.failf "%s: expected an error result" label
  | Error error -> error

let expect_some label = function
  | Some value -> value
  | None -> Alcotest.failf "%s: expected a present member" label

(* ^njson-7pjx ^njson-3ph9: [compact] is [to_string], and the text is one
   compact line. *)
let test_compact_rendering () =
  let document =
    Ox_json.object_
      [
        ("text", Some (Ox_json.string "a\nb"));
        ("count", Some (Ox_json.int 3));
        ("flag", Some (Ox_json.bool true));
        ("ratio", Ox_json.float 0.5);
        ("absent", None);
      ]
  in
  let text = Ox_json.to_string document in
  Alcotest.(check string) "compact equals to_string" text (Ox_json.compact document);
  Alcotest.(check bool) "single line" false (String.contains text '\n');
  Alcotest.(check string)
    "exact compact bytes" "{\"text\":\"a\\nb\",\"count\":3,\"flag\":true,\"ratio\":0.5}"
    text;
  Alcotest.(check json)
    "parse of the compact text" document
    (expect_ok "compact rendering" (Ox_json.parse text))

(* ^njson-7pjx ^njson-3ph9: malformed text is an error result, not an
   exception. *)
let test_parse_rejects_invalid () =
  List.iter
    (fun raw ->
      match expect_error ("invalid " ^ raw) (Ox_json.parse raw) with
      | `Malformed _ -> ()
      | `Too_large _ ->
          Alcotest.failf "invalid %s: malformed text must not report the bound" raw)
    [ ""; "{"; "[1, 2"; "{\"a\": }"; "nope"; "{\"a\": 1} trailing" ]

(* ^njson-nc66 ^njson-3ph9: the byte bound rejects oversized input before it is
   parsed, and names the bound and the length in the refusal. *)
let test_parse_max_bytes () =
  let raw = "{\"a\": 1}" in
  let bound = String.length raw in
  Alcotest.(check json)
    "input at the bound"
    (Ox_json.object_ [ ("a", Some (Ox_json.int 1)) ])
    (expect_ok "at the bound" (Ox_json.parse ~max_bytes:bound raw));
  let error =
    expect_error "one byte over the bound" (Ox_json.parse ~max_bytes:(bound - 1) raw)
  in
  (match error with
  | `Too_large { limit; length } ->
      Alcotest.(check int) "bound named" (bound - 1) limit;
      Alcotest.(check int) "length named" bound length
  | `Malformed message ->
      Alcotest.failf "over the bound must be a bound refusal, got %s" message);
  Alcotest.(check string)
    "printer names the bound" "JSON input of 8 bytes exceeds max_bytes (7)"
    (Format.asprintf "%a" Ox_json.pp_parse_error error);
  (* Valid JSON over the bound is refused before any value is built. *)
  (match Ox_json.parse ~max_bytes:1 "{}" with
  | Error (`Too_large { limit = 1; length = 2 }) -> ()
  | Error _ | Ok _ -> Alcotest.fail "valid JSON over the bound must be refused");
  (match Ox_json.parse ~max_bytes:0 raw with
  | Error (`Too_large _) -> ()
  | Error _ | Ok _ -> Alcotest.fail "a zero bound refuses any input");
  let raised =
    try
      ((* ^safe-xls8 ^safe-pufa ^nlint-hxar: The negative bound must raise Invalid_argument; any normal return makes the existing raised assertion false. *)
       let _parse_result =
         Ox_json.parse ~max_bytes:(-1) raw
           [@@ox.allow
             "ox-discarded-result: negative max_bytes must raise Invalid_argument; a \
              normal return fails the raised assertion"]
       in
       ());
      false
    with Invalid_argument _ -> true
  in
  Alcotest.(check bool) "negative bound is an invalid argument" true raised

(* ^njson-7pjx ^njson-3ph9: an absent field is omitted, a present field keeps
   its name and position. *)
let test_object_omits_absent () =
  let document =
    Ox_json.object_
      [ ("a", Some (Ox_json.int 1)); ("b", None); ("c", Some (Ox_json.bool false)) ]
  in
  Alcotest.(check string)
    "absent field omitted" "{\"a\":1,\"c\":false}" (Ox_json.to_string document);
  Alcotest.(check json)
    "kept field is readable" (Ox_json.bool false)
    (expect_some "kept field" (Ox_json.member "c" document));
  Alcotest.(check (option json))
    "omitted field stays absent" None (Ox_json.member "b" document);
  Alcotest.(check string) "no fields" "{}" (Ox_json.to_string (Ox_json.object_ []))

(* ^njson-7pjx ^njson-3ph9: scalar constructors, including the non-finite
   rejection of the float surface. *)
let test_scalar_constructors () =
  Alcotest.(check json) "string" (`String "ox") (Ox_json.string "ox");
  Alcotest.(check json) "bool" (`Bool true) (Ox_json.bool true);
  Alcotest.(check json) "int" (`Int 9) (Ox_json.int 9);
  Alcotest.(check (option json)) "finite float" (Some (`Float 1.5)) (Ox_json.float 1.5);
  Alcotest.(check (option json)) "nan" None (Ox_json.float Float.nan);
  Alcotest.(check (option json)) "infinity" None (Ox_json.float Float.infinity);
  Alcotest.(check (option json))
    "negative infinity" None
    (Ox_json.float Float.neg_infinity);
  Alcotest.(check json)
    "array"
    (`List [ `Int 1; `String "two" ])
    (Ox_json.array [ Ox_json.int 1; Ox_json.string "two" ]);
  Alcotest.(check string) "empty array" "[]" (Ox_json.to_string (Ox_json.array []));
  Alcotest.(check json)
    "array_map keeps input order"
    (`List [ `Int 2; `Int 4 ])
    (Ox_json.array_map (fun value -> Ox_json.int (value * 2)) [ 1; 2 ])

(* ^njson-7pjx ^njson-3ph9: member reads on a present, a missing, and a
   wrong-typed member; a non-object input has no members at all. *)
let test_member_accessors () =
  let document =
    Ox_json.object_
      [
        ("name", Some (Ox_json.string "ox"));
        ("count", Some (Ox_json.int 7));
        ("big", Some (`Intlit "42"));
        ("ratio", Some (`Float 2.0));
        ("half", Some (`Float 0.5));
        ("flag", Some (Ox_json.bool true));
        ("items", Some (Ox_json.array [ Ox_json.int 1 ]));
        ("nested", Some (Ox_json.object_ [ ("inner", Some (Ox_json.bool true)) ]));
        ("nothing", Some `Null);
      ]
  in
  let absent = "absent" in
  Alcotest.(check (option json))
    "member present"
    (Some (Ox_json.string "ox"))
    (Ox_json.member "name" document);
  Alcotest.(check (option json)) "member missing" None (Ox_json.member absent document);
  Alcotest.(check (option json))
    "member of a non-object" None
    (Ox_json.member "name" (`String "ox"));
  Alcotest.(check (option string))
    "string_member present" (Some "ox")
    (Ox_json.string_member "name" document);
  Alcotest.(check (option string))
    "string_member missing" None
    (Ox_json.string_member absent document);
  Alcotest.(check (option string))
    "string_member wrong type" None
    (Ox_json.string_member "count" document);
  Alcotest.(check (option string))
    "scalar_string_member string" (Some "ox")
    (Ox_json.scalar_string_member "name" document);
  Alcotest.(check (option string))
    "scalar_string_member int" (Some "7")
    (Ox_json.scalar_string_member "count" document);
  Alcotest.(check (option string))
    "scalar_string_member intlit" (Some "42")
    (Ox_json.scalar_string_member "big" document);
  Alcotest.(check (option string))
    "scalar_string_member float" (Some "2")
    (Ox_json.scalar_string_member "ratio" document);
  Alcotest.(check (option string))
    "scalar_string_member bool" (Some "true")
    (Ox_json.scalar_string_member "flag" document);
  Alcotest.(check (option string))
    "scalar_string_member missing" None
    (Ox_json.scalar_string_member absent document);
  Alcotest.(check (option string))
    "scalar_string_member array" None
    (Ox_json.scalar_string_member "items" document);
  Alcotest.(check (option string))
    "scalar_string_member null" None
    (Ox_json.scalar_string_member "nothing" document);
  Alcotest.(check (option int))
    "int_member int" (Some 7)
    (Ox_json.int_member "count" document);
  Alcotest.(check (option int))
    "int_member intlit" (Some 42)
    (Ox_json.int_member "big" document);
  Alcotest.(check (option int))
    "int_member integral float" (Some 2)
    (Ox_json.int_member "ratio" document);
  Alcotest.(check (option int))
    "int_member fractional float" None
    (Ox_json.int_member "half" document);
  Alcotest.(check (option int))
    "int_member string" None
    (Ox_json.int_member "name" document);
  Alcotest.(check (option int))
    "int_member missing" None
    (Ox_json.int_member absent document);
  Alcotest.(check (option (list json)))
    "array_member present"
    (Some [ Ox_json.int 1 ])
    (Ox_json.array_member "items" document);
  Alcotest.(check (option (list json)))
    "array_member missing" None
    (Ox_json.array_member absent document);
  Alcotest.(check (option (list json)))
    "array_member wrong type" None
    (Ox_json.array_member "count" document);
  Alcotest.(check (option json))
    "object_member present"
    (Some (Ox_json.object_ [ ("inner", Some (Ox_json.bool true)) ]))
    (Ox_json.object_member "nested" document);
  Alcotest.(check (option json))
    "object_member missing" None
    (Ox_json.object_member absent document);
  Alcotest.(check (option json))
    "object_member wrong type" None
    (Ox_json.object_member "items" document)

(* ^njson-7pjx ^njson-3ph9: every accessor reports an absent name as [None]. *)
let test_accessors_ignore_absent_members () =
  let document = Ox_json.object_ [ ("present", Some (Ox_json.string "x")) ] in
  List.iter
    (fun check -> Alcotest.(check bool) "absent member" true (check ()))
    [
      (fun () -> Ox_json.member "absent" document = None);
      (fun () -> Ox_json.string_member "absent" document = None);
      (fun () -> Ox_json.scalar_string_member "absent" document = None);
      (fun () -> Ox_json.int_member "absent" document = None);
      (fun () -> Ox_json.array_member "absent" document = None);
      (fun () -> Ox_json.object_member "absent" document = None);
    ]

(* ^nnoschema-44wj: the Leash control-protocol smoke test, rewritten as a derived
   round-trip. The two request types are plain records with [@@deriving yojson] and
   the example is Leash's docs/protocol.md envelope, copied verbatim (the ellipsis
   is U+2026). It replaces ^nschema-yyfu's schema-built version: the shape is the
   type, so there is nothing to keep in step with it. *)
type leash_args = { tab : string; index : int } [@@deriving yojson]

type leash_request = { v : int; owner : string; cmd : string; args : leash_args }
[@@deriving yojson]

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search index =
    if index + needle_length > haystack_length then false
    else if String.equal (String.sub haystack index needle_length) needle then true
    else search (index + 1)
  in
  needle_length = 0 || search 0

let leash_example =
  {|{"v":1,"owner":"dsh:4f2a…","cmd":"click","args":{"tab":"t_9xk…","index":7}}|}

let test_leash_protocol_derived () =
  let external_json = Yojson.Safe.from_string leash_example in
  let decoded =
    match leash_request_of_yojson external_json with
    | Ok request -> request
    | Error message -> Alcotest.failf "leash example: %s" message
  in
  Alcotest.(check int) "v" 1 decoded.v;
  Alcotest.(check string) "owner" "dsh:4f2a…" decoded.owner;
  Alcotest.(check string) "cmd" "click" decoded.cmd;
  Alcotest.(check string) "args.tab" "t_9xk…" decoded.args.tab;
  Alcotest.(check int) "args.index" 7 decoded.args.index;
  Alcotest.(check bool)
    "the derived encoder reproduces the example byte for byte" true
    (Yojson.Safe.equal external_json (yojson_of_leash_request decoded));
  (* ^nnoschema-zi2m: a wrong-typed field names its path, restarts it at the nested
     type, and carries the offending subtree — what invalid-request renders. *)
  let bad =
    Yojson.Safe.from_string
      {|{"v":1,"owner":"dsh:x","cmd":"click","args":{"tab":"t","index":"seven"}}|}
  in
  match leash_request_of_yojson bad with
  | Ok _ -> Alcotest.fail "expected a decode failure"
  | Error message ->
      List.iter
        (fun needle ->
          Alcotest.(check bool) ("error names " ^ needle) true (contains message needle))
        [ "leash_request.args"; "index"; "expected int"; "\"seven\"" ];
      (* ^njson-cdp0: JSON whose shape belongs to a peer — a CDP frame, say — stays
         unchecked through Ox_json and survives a parse/compact round-trip whatever
         fields it carries. *)
      let cdp =
        {|{"id":7,"method":"Page.navigate","params":{"url":"about:blank"},"consumed":true}|}
      in
      let parsed =
        match Ox_json.parse cdp with
        | Ok value -> value
        | Error error ->
            Alcotest.failf "unchecked JSON parses: %a" Ox_json.pp_parse_error error
      in
      Alcotest.(check string)
        "the peer's shape round-trips byte for byte" cdp (Ox_json.to_string parsed)

(* ^nderive-vq4n: dynamic JSON — a CDP payload, say — is read by composing decoders, and a
   failure is an [Ox_json.issue] carrying the path of the value that did not fit. *)
module Decode = Ox_json.Of_json

let cdp =
  Yojson.Safe.from_string
    {|{"id":7,"method":"Page.navigate","params":{"url":"about:blank"},"consumed":true}|}

let decoded label = function
  | Ok value -> value
  | Error issue -> Alcotest.failf "%s: unexpected failure %a" label Ox_json.pp_issue issue

let issue label decoder input =
  match decoder input with
  | Ok _ -> Alcotest.failf "%s: expected a decoder failure" label
  | Error issue -> issue

let check_issue label ~path ~message ~got decoder input =
  let { Ox_json.path = actual_path; message = actual_message; got = actual_got } =
    issue label decoder input
  in
  Alcotest.(check string) (label ^ ": path") path actual_path;
  Alcotest.(check string) (label ^ ": message") message actual_message;
  Alcotest.(check json) (label ^ ": value") got actual_got

(* ^nderive-vq4n: each primitive accepts its own JSON shape, with the coercions the
   deriver makes, and refuses every other shape with what it expected and the value. *)
let test_of_json_primitives () =
  Alcotest.(check string) "string" "ox" (decoded "string" (Decode.string (`String "ox")));
  Alcotest.(check bool) "bool" true (decoded "bool" (Decode.bool (`Bool true)));
  Alcotest.(check int) "int" 7 (decoded "int" (Decode.int (`Int 7)));
  Alcotest.(check int)
    "integer literal" 42
    (decoded "literal" (Decode.int (`Intlit "42")));
  Alcotest.(check (float 0.0)) "float" 1.5 (decoded "float" (Decode.float (`Float 1.5)));
  Alcotest.(check (float 0.0))
    "an integer widens to float" 2.0
    (decoded "int as float" (Decode.float (`Int 2)));
  Alcotest.(check unit) "null" () (decoded "null" (Decode.null `Null));
  check_issue "a float is not an int" ~path:"" ~message:"expected int" ~got:(`Float 3.0)
    Decode.int (`Float 3.0);
  check_issue "an overflowing literal" ~path:"" ~message:"expected int"
    ~got:(`Intlit "99999999999999999999999") Decode.int
    (`Intlit "99999999999999999999999");
  check_issue "a string is not a number" ~path:"" ~message:"expected number"
    ~got:(`String "x") Decode.float (`String "x");
  check_issue "a bool is not a string" ~path:"" ~message:"expected string"
    ~got:(`Bool true) Decode.string (`Bool true);
  Alcotest.(check string)
    "the issue renders like the deriver does" "expected string, got true"
    (Format.asprintf "%a" Ox_json.pp_issue (issue "render" Decode.string (`Bool true)))

(* ^nderive-vq4n: members are read by name, and the path grows with each read. *)
let test_of_json_field_and_at () =
  Alcotest.(check string)
    "field" "Page.navigate"
    (decoded "method" (Decode.field "method" Decode.string cdp));
  Alcotest.(check string)
    "at" "about:blank"
    (decoded "url" (Decode.at [ "params"; "url" ] Decode.string cdp));
  check_issue "a wrong-typed member" ~path:"params.url" ~message:"expected string"
    ~got:(`Int 7)
    (Decode.at [ "params"; "url" ] Decode.string)
    (`Assoc [ ("params", `Assoc [ ("url", `Int 7) ]) ]);
  check_issue "a missing member is reported at the path of the object" ~path:"params"
    ~message:"missing field url" ~got:(`Assoc [])
    (Decode.at [ "params"; "url" ] Decode.string)
    (`Assoc [ ("params", `Assoc []) ]);
  check_issue "a non-object" ~path:"" ~message:"expected object" ~got:(`List [])
    (Decode.field "method" Decode.string)
    (`List [])

(* ^nderive-vq4n: an element failure is at the field path plus the index, the deriver
   convention. *)
let test_of_json_list_path () =
  Alcotest.(check (list int))
    "list" [ 1; 2 ]
    (decoded "ids" (Decode.list Decode.int (`List [ `Int 1; `Int 2 ])));
  check_issue "a bad element" ~path:"ids.[1]" ~message:"expected int" ~got:(`String "x")
    (Decode.field "ids" (Decode.list Decode.int))
    (`Assoc [ ("ids", `List [ `Int 1; `String "x" ]) ]);
  check_issue "a non-array" ~path:"" ~message:"expected array" ~got:(`Int 1)
    (Decode.list Decode.int) (`Int 1)

(* ^nderive-vq4n: [option] is the explicit-null encoding; [try_or_none] is the read that
   turns any failure into None, which is how an absent or foreign member is tolerated. *)
let test_of_json_option_and_try_or_none () =
  Alcotest.(check (option int))
    "null is None" None
    (decoded "none" (Decode.option Decode.int `Null));
  Alcotest.(check (option int))
    "a value is Some" (Some 3)
    (decoded "some" (Decode.option Decode.int (`Int 3)));
  check_issue "option does not swallow a failure" ~path:"" ~message:"expected int"
    ~got:(`String "x") (Decode.option Decode.int) (`String "x");
  Alcotest.(check (option int))
    "try_or_none on an absent member" None
    (decoded "absent"
       (Decode.try_or_none (Decode.field "thickness" Decode.int) (`Assoc [])));
  Alcotest.(check (option int))
    "try_or_none on a wrong shape" None
    (decoded "wrong"
       (Decode.try_or_none
          (Decode.field "thickness" Decode.int)
          (`Assoc [ ("thickness", `String "x") ])));
  Alcotest.(check (option int))
    "try_or_none on a value" (Some 4)
    (decoded "value"
       (Decode.try_or_none
          (Decode.field "thickness" Decode.int)
          (`Assoc [ ("thickness", `Int 4) ])))

(* ^nderive-vq4n: [one_of] takes the first alternative that accepts the value, and names
   the value itself when none does. *)
let test_of_json_one_of () =
  let name_or_id =
    Decode.one_of [ Decode.field "name" Decode.string; Decode.field "id" Decode.string ]
  in
  Alcotest.(check string)
    "the first alternative" "ox"
    (decoded "first" (name_or_id (`Assoc [ ("name", `String "ox") ])));
  Alcotest.(check string)
    "the second alternative" "7"
    (decoded "second" (name_or_id (`Assoc [ ("id", `String "7") ])));
  check_issue "no alternative matched" ~path:"args"
    ~message:"expected one of the alternatives" ~got:(`Bool true)
    (Decode.field "args" name_or_id)
    (`Assoc [ ("args", `Bool true) ]);
  check_issue "an empty alternative list never matches" ~path:""
    ~message:"expected one of the alternatives" ~got:`Null
    (Decode.one_of [] : unit Ox_json.Of_json.t)
    `Null

(* ^nderive-vq4n: a decoder is a total read — any JSON value is an Ok or an issue, never
   an exception, whatever shape a peer sent. *)
let test_of_json_never_raises () =
  let exotic =
    [
      `Null;
      `Bool true;
      `Int 1;
      `Intlit "1";
      `Float 1.0;
      `String "x";
      `Assoc [ ("a", `Null) ];
      `List [ `Null ];
      `Tuple [ `Int 1 ];
      `Variant ("V", None);
    ]
  in
  let attempts =
    [
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.string json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.bool json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.int json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.float json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.null json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.list Decode.int json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.option Decode.int json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.field "a" Decode.int json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.at [ "a"; "b" ] Decode.int json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.one_of [ Decode.field "a" Decode.int; Decode.field "b" Decode.int ] json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          Decode.try_or_none (Decode.field "a" Decode.string) json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
      (fun json ->
        (* ^safe-xls8 ^safe-pufa ^nlint-hxar: This totality matrix accepts either Ok or Error; its only failure is a decoder raising on an input. *)
        let _decode_result =
          (Decode.one_of [] : unit Ox_json.Of_json.t) json
            [@@ox.allow
              "ox-discarded-result: decoder totality matrix accepts either success or \
               refusal and fails only when decoding raises"]
        in
        ());
    ]
  in
  List.iter
    (fun json ->
      List.iter
        (fun attempt ->
          match attempt json with
          | () -> ()
          | exception error ->
              Alcotest.failf "a decoder raised %s on %s" (Printexc.to_string error)
                (Ox_json.to_string json))
        attempts)
    exotic

let () =
  Alcotest.run "ox_json"
    [
      ( "helpers",
        [
          Alcotest.test_case "njson-7pjx njson-3ph9 compact rendering" `Quick
            test_compact_rendering;
          Alcotest.test_case "njson-7pjx njson-3ph9 invalid text is a result" `Quick
            test_parse_rejects_invalid;
          Alcotest.test_case "njson-nc66 njson-3ph9 max_bytes bound" `Quick
            test_parse_max_bytes;
          Alcotest.test_case "njson-7pjx njson-3ph9 object_ omits absent fields" `Quick
            test_object_omits_absent;
          Alcotest.test_case "njson-7pjx njson-3ph9 scalar constructors" `Quick
            test_scalar_constructors;
          Alcotest.test_case "njson-7pjx njson-3ph9 member accessors" `Quick
            test_member_accessors;
          Alcotest.test_case "njson-7pjx njson-3ph9 absent members stay absent" `Quick
            test_accessors_ignore_absent_members;
        ] );
      ( "protocol",
        [
          Alcotest.test_case
            "^nnoschema-44wj ^nnoschema-zi2m ^njson-cdp0 leash request as a derived type"
            `Quick test_leash_protocol_derived;
        ] );
      ( "of_json",
        [
          Alcotest.test_case "nderive-vq4n primitives" `Quick test_of_json_primitives;
          Alcotest.test_case "nderive-vq4n field and at" `Quick test_of_json_field_and_at;
          Alcotest.test_case "nderive-vq4n list element path" `Quick
            test_of_json_list_path;
          Alcotest.test_case "nderive-vq4n option and try_or_none" `Quick
            test_of_json_option_and_try_or_none;
          Alcotest.test_case "nderive-vq4n one_of" `Quick test_of_json_one_of;
          Alcotest.test_case "nderive-vq4n decoders never raise" `Quick
            test_of_json_never_raises;
        ] );
    ]
