(* Unit tests for the eta_json package.

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
   Eta_json (^njson-cdp0): shapes we own derive their codec, shapes a peer owns
   do not. *)

(* ^njson-7pjx: the value type is [Yojson.Safe.t] itself, not a copy. *)
let (_ : Eta_json.t -> Yojson.Safe.t) = fun value -> value
let (_ : Yojson.Safe.t -> Eta_json.t) = fun value -> value

let json =
  Alcotest.testable
    (fun ppf value -> Format.pp_print_string ppf (Eta_json.to_string value))
    (fun left right -> String.equal (Eta_json.to_string left) (Eta_json.to_string right))

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      Alcotest.failf "%s: unexpected error %a" label Eta_json.pp_parse_error error

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
    Eta_json.object_
      [
        ("text", Some (Eta_json.string "a\nb"));
        ("count", Some (Eta_json.int 3));
        ("flag", Some (Eta_json.bool true));
        ("ratio", Eta_json.float 0.5);
        ("absent", None);
      ]
  in
  let text = Eta_json.to_string document in
  Alcotest.(check string) "compact equals to_string" text (Eta_json.compact document);
  Alcotest.(check bool) "single line" false (String.contains text '\n');
  Alcotest.(check string)
    "exact compact bytes" "{\"text\":\"a\\nb\",\"count\":3,\"flag\":true,\"ratio\":0.5}"
    text;
  Alcotest.(check json)
    "parse of the compact text" document
    (expect_ok "compact rendering" (Eta_json.parse text))

(* ^njson-7pjx ^njson-3ph9: malformed text is an error result, not an
   exception. *)
let test_parse_rejects_invalid () =
  List.iter
    (fun raw ->
      match expect_error ("invalid " ^ raw) (Eta_json.parse raw) with
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
    (Eta_json.object_ [ ("a", Some (Eta_json.int 1)) ])
    (expect_ok "at the bound" (Eta_json.parse ~max_bytes:bound raw));
  let error =
    expect_error "one byte over the bound" (Eta_json.parse ~max_bytes:(bound - 1) raw)
  in
  (match error with
  | `Too_large { limit; length } ->
      Alcotest.(check int) "bound named" (bound - 1) limit;
      Alcotest.(check int) "length named" bound length
  | `Malformed message ->
      Alcotest.failf "over the bound must be a bound refusal, got %s" message);
  Alcotest.(check string)
    "printer names the bound" "JSON input of 8 bytes exceeds max_bytes (7)"
    (Format.asprintf "%a" Eta_json.pp_parse_error error);
  (* Valid JSON over the bound is refused before any value is built. *)
  (match Eta_json.parse ~max_bytes:1 "{}" with
  | Error (`Too_large { limit = 1; length = 2 }) -> ()
  | Error _ | Ok _ -> Alcotest.fail "valid JSON over the bound must be refused");
  (match Eta_json.parse ~max_bytes:0 raw with
  | Error (`Too_large _) -> ()
  | Error _ | Ok _ -> Alcotest.fail "a zero bound refuses any input");
  let raised =
    try
      ignore (Eta_json.parse ~max_bytes:(-1) raw);
      false
    with Invalid_argument _ -> true
  in
  Alcotest.(check bool) "negative bound is an invalid argument" true raised

(* ^njson-7pjx ^njson-3ph9: an absent field is omitted, a present field keeps
   its name and position. *)
let test_object_omits_absent () =
  let document =
    Eta_json.object_
      [ ("a", Some (Eta_json.int 1)); ("b", None); ("c", Some (Eta_json.bool false)) ]
  in
  Alcotest.(check string)
    "absent field omitted" "{\"a\":1,\"c\":false}" (Eta_json.to_string document);
  Alcotest.(check json)
    "kept field is readable" (Eta_json.bool false)
    (expect_some "kept field" (Eta_json.member "c" document));
  Alcotest.(check (option json))
    "omitted field stays absent" None
    (Eta_json.member "b" document);
  Alcotest.(check string) "no fields" "{}" (Eta_json.to_string (Eta_json.object_ []))

(* ^njson-7pjx ^njson-3ph9: scalar constructors, including the non-finite
   rejection of the float surface. *)
let test_scalar_constructors () =
  Alcotest.(check json) "string" (`String "eta") (Eta_json.string "eta");
  Alcotest.(check json) "bool" (`Bool true) (Eta_json.bool true);
  Alcotest.(check json) "int" (`Int 9) (Eta_json.int 9);
  Alcotest.(check (option json)) "finite float" (Some (`Float 1.5)) (Eta_json.float 1.5);
  Alcotest.(check (option json)) "nan" None (Eta_json.float Float.nan);
  Alcotest.(check (option json)) "infinity" None (Eta_json.float Float.infinity);
  Alcotest.(check (option json))
    "negative infinity" None
    (Eta_json.float Float.neg_infinity);
  Alcotest.(check json)
    "array"
    (`List [ `Int 1; `String "two" ])
    (Eta_json.array [ Eta_json.int 1; Eta_json.string "two" ]);
  Alcotest.(check string) "empty array" "[]" (Eta_json.to_string (Eta_json.array []));
  Alcotest.(check json)
    "array_map keeps input order"
    (`List [ `Int 2; `Int 4 ])
    (Eta_json.array_map (fun value -> Eta_json.int (value * 2)) [ 1; 2 ])

(* ^njson-7pjx ^njson-3ph9: member reads on a present, a missing, and a
   wrong-typed member; a non-object input has no members at all. *)
let test_member_accessors () =
  let document =
    Eta_json.object_
      [
        ("name", Some (Eta_json.string "eta"));
        ("count", Some (Eta_json.int 7));
        ("big", Some (`Intlit "42"));
        ("ratio", Some (`Float 2.0));
        ("half", Some (`Float 0.5));
        ("flag", Some (Eta_json.bool true));
        ("items", Some (Eta_json.array [ Eta_json.int 1 ]));
        ("nested", Some (Eta_json.object_ [ ("inner", Some (Eta_json.bool true)) ]));
        ("nothing", Some `Null);
      ]
  in
  let absent = "absent" in
  Alcotest.(check (option json))
    "member present"
    (Some (Eta_json.string "eta"))
    (Eta_json.member "name" document);
  Alcotest.(check (option json)) "member missing" None (Eta_json.member absent document);
  Alcotest.(check (option json))
    "member of a non-object" None
    (Eta_json.member "name" (`String "eta"));
  Alcotest.(check (option string))
    "string_member present" (Some "eta")
    (Eta_json.string_member "name" document);
  Alcotest.(check (option string))
    "string_member missing" None
    (Eta_json.string_member absent document);
  Alcotest.(check (option string))
    "string_member wrong type" None
    (Eta_json.string_member "count" document);
  Alcotest.(check (option string))
    "scalar_string_member string" (Some "eta")
    (Eta_json.scalar_string_member "name" document);
  Alcotest.(check (option string))
    "scalar_string_member int" (Some "7")
    (Eta_json.scalar_string_member "count" document);
  Alcotest.(check (option string))
    "scalar_string_member intlit" (Some "42")
    (Eta_json.scalar_string_member "big" document);
  Alcotest.(check (option string))
    "scalar_string_member float" (Some "2")
    (Eta_json.scalar_string_member "ratio" document);
  Alcotest.(check (option string))
    "scalar_string_member bool" (Some "true")
    (Eta_json.scalar_string_member "flag" document);
  Alcotest.(check (option string))
    "scalar_string_member missing" None
    (Eta_json.scalar_string_member absent document);
  Alcotest.(check (option string))
    "scalar_string_member array" None
    (Eta_json.scalar_string_member "items" document);
  Alcotest.(check (option string))
    "scalar_string_member null" None
    (Eta_json.scalar_string_member "nothing" document);
  Alcotest.(check (option int))
    "int_member int" (Some 7)
    (Eta_json.int_member "count" document);
  Alcotest.(check (option int))
    "int_member intlit" (Some 42)
    (Eta_json.int_member "big" document);
  Alcotest.(check (option int))
    "int_member integral float" (Some 2)
    (Eta_json.int_member "ratio" document);
  Alcotest.(check (option int))
    "int_member fractional float" None
    (Eta_json.int_member "half" document);
  Alcotest.(check (option int))
    "int_member string" None
    (Eta_json.int_member "name" document);
  Alcotest.(check (option int))
    "int_member missing" None
    (Eta_json.int_member absent document);
  Alcotest.(check (option (list json)))
    "array_member present"
    (Some [ Eta_json.int 1 ])
    (Eta_json.array_member "items" document);
  Alcotest.(check (option (list json)))
    "array_member missing" None
    (Eta_json.array_member absent document);
  Alcotest.(check (option (list json)))
    "array_member wrong type" None
    (Eta_json.array_member "count" document);
  Alcotest.(check (option json))
    "object_member present"
    (Some (Eta_json.object_ [ ("inner", Some (Eta_json.bool true)) ]))
    (Eta_json.object_member "nested" document);
  Alcotest.(check (option json))
    "object_member missing" None
    (Eta_json.object_member absent document);
  Alcotest.(check (option json))
    "object_member wrong type" None
    (Eta_json.object_member "items" document)

(* ^njson-7pjx ^njson-3ph9: every accessor reports an absent name as [None]. *)
let test_accessors_ignore_absent_members () =
  let document = Eta_json.object_ [ ("present", Some (Eta_json.string "x")) ] in
  List.iter
    (fun check -> Alcotest.(check bool) "absent member" true (check ()))
    [
      (fun () -> Eta_json.member "absent" document = None);
      (fun () -> Eta_json.string_member "absent" document = None);
      (fun () -> Eta_json.scalar_string_member "absent" document = None);
      (fun () -> Eta_json.int_member "absent" document = None);
      (fun () -> Eta_json.array_member "absent" document = None);
      (fun () -> Eta_json.object_member "absent" document = None);
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
         unchecked through Eta_json and survives a parse/compact round-trip whatever
         fields it carries. *)
      let cdp =
        {|{"id":7,"method":"Page.navigate","params":{"url":"about:blank"},"consumed":true}|}
      in
      let parsed =
        match Eta_json.parse cdp with
        | Ok value -> value
        | Error error ->
            Alcotest.failf "unchecked JSON parses: %a" Eta_json.pp_parse_error error
      in
      Alcotest.(check string)
        "the peer's shape round-trips byte for byte" cdp (Eta_json.to_string parsed)

let () =
  Alcotest.run "eta_json"
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
    ]
