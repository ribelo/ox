(* Tests for the eta_schema_yojson bridge.

   ^njson-35ih: [of_yojson] and [to_yojson] carry every Yojson.Safe.t shape
   across the bridge and report invalid external data as issues; [decode_result]
   and [encode_result] are the two directions a service uses.
   ^njson-3ph9: the pure parts of v1's adapter suite, ported from the effect
   layer to the direct [result] surface.
   ^njson-fib9: adapter conversion attaches the input location while it
   descends, so an issue names the field or index that produced it.
   ^nschema-59sn: the encoder direction reproduces the declared wire shape.
   ^nschema-yyfu: Leash's protocol example request from docs/protocol.md decodes
   through a schema and encodes back to the same document. *)

let json_testable =
  Alcotest.testable
    (fun fmt json -> Format.pp_print_string fmt (Eta_schema.Json.to_string json))
    Eta_schema.Json.equal

let expect_ok label = function
  | Ok value -> value
  | Error issues ->
      Alcotest.failf "%s: %s" label (Eta_schema.render_issues issues)

let decode_ok ?(name = "decode") schema external_json =
  expect_ok name (Eta_schema_yojson.decode_result schema external_json)

let encode_ok ?(name = "encode") schema value =
  expect_ok name (Eta_schema_yojson.encode_result schema value)

let json_string value =
  match Eta_schema.Json.string value with
  | Ok json -> json
  | Error issues ->
      Alcotest.failf "invalid JSON string fixture: %s"
        (Eta_schema.render_issues issues)

let json_object fields =
  match Eta_schema.Json.object_ fields with
  | Ok json -> json
  | Error issues ->
      Alcotest.failf "invalid JSON object fixture: %s"
        (Eta_schema.render_issues issues)

(* ^njson-35ih ^njson-3ph9: every Yojson shape crosses the bridge unchanged. *)
let test_round_trip () =
  let input =
    `Assoc
      [
        ("null", `Null);
        ("bool", `Bool true);
        ("int", `Int 3);
        ("intlit", `Intlit "9007199254740993");
        ("float", `Float 1.5);
        ("text", `String "value");
        ("array", `List [ `Int 1; `Int 2 ]);
      ]
  in
  let converted = expect_ok "of_yojson" (Eta_schema_yojson.of_yojson input) in
  Alcotest.(check string)
    "round trip" (Yojson.Safe.to_string input)
    (Yojson.Safe.to_string (Eta_schema_yojson.to_yojson converted))

(* ^njson-35ih: non-finite floats, malformed number literals, invalid UTF-8 and
   the non-standard Yojson extensions are issues, not exceptions. *)
let test_reject_malformed_external_data () =
  let rejected label external_json =
    match Eta_schema_yojson.of_yojson external_json with
    | Ok _ -> Alcotest.failf "%s: expected adapter rejection" label
    | Error issues ->
        Alcotest.(check bool) (label ^ " reports issues") true (issues <> [])
  in
  List.iter
    (fun literal -> rejected ("intlit " ^ literal) (`Intlit literal))
    [ ""; "-"; "01"; "+1"; "1."; ".5"; "1e"; "0x10"; " 1"; "1 " ];
  rejected "non-finite" (`Float Float.infinity);
  rejected "negative non-finite" (`Float Float.neg_infinity);
  rejected "nan" (`Float Float.nan);
  rejected "invalid utf8 value" (`String "\xff");
  rejected "truncated utf8 value" (`String "\xc3");
  rejected "invalid utf8 name" (`Assoc [ ("ok", `Int 1); ("bad\xff", `Int 2) ]);
  rejected "tuple extension" (`Tuple [ `Int 1 ]);
  rejected "variant extension" (`Variant ("a", None));
  rejected "nested invalid value" (`List [ `Int 1; `String "\xff" ])

(* ^njson-35ih: a root schema decodes through the adapter without opening the
   module. *)
let test_root_adapter_without_open () =
  match Eta_schema_yojson.decode_result Eta_schema.int (`Int 8) with
  | Ok 8 -> ()
  | Ok value -> Alcotest.failf "unexpected adapter int %d" value
  | Error issues ->
      Alcotest.failf "adapter root decode failed: %s"
        (Eta_schema.render_issues issues)

(* ^njson-3ph9: valid large literals stay exact and constructed trees serialize
   and parse back. *)
let test_large_literal_and_serialization_roundtrip () =
  let literal = "18446744073709551616" in
  let json =
    expect_ok "large literal" (Eta_schema_yojson.of_yojson (`Intlit literal))
  in
  (match Eta_schema_yojson.to_yojson json with
  | `Intlit value -> Alcotest.(check string) "literal preserved" literal value
  | _ -> Alcotest.fail "large literal changed representation");
  let tree =
    json_object
      [
        ("nested", Eta_schema.Json.array [ Eta_schema.Json.null ]);
        ("text", json_string "\xc3\xa9\n");
        ("intlit", json);
      ]
  in
  let parsed =
    Eta_schema_yojson.of_yojson
      (Yojson.Safe.from_string (Eta_schema.Json.to_string tree))
  in
  match parsed with
  | Ok parsed ->
      Alcotest.(check bool)
        "serialized tree round trips" true
        (Eta_schema.Json.equal tree parsed)
  | Error issues ->
      Alcotest.failf "serialized tree did not parse back: %s"
        (Eta_schema.render_issues issues)

(* ^njson-fib9 ^njson-3ph9: adapter conversion attaches the input location while
   descending: a failing element carries its index, a failing field its name. *)
let test_adapter_issue_paths () =
  let adapter_issue label external_json =
    match Eta_schema_yojson.of_yojson external_json with
    | Ok _ -> Alcotest.failf "%s: expected adapter rejection" label
    | Error issues ->
        Alcotest.(check int) (label ^ " issue count") 1 (List.length issues);
        List.hd issues
  in
  let pointer label external_json =
    Eta_schema.issue_to_json_pointer (adapter_issue label external_json)
  in
  Alcotest.(check string) "root pointer" ""
    (pointer "root" (`Float Float.infinity));
  Alcotest.(check string) "nested array pointer" "/0/1"
    (pointer "nested array" (`List [ `List [ `Int 0; `Float Float.infinity ] ]));
  Alcotest.(check string) "field plus index pointer" "/a~1b/1"
    (pointer "field plus index" (`Assoc [ ("a/b", `List [ `Int 0; `Tuple [] ]) ]));
  Alcotest.(check string) "tilde field pointer" "/a~0b"
    (pointer "tilde field" (`Assoc [ ("a~b", `Intlit "01") ]));
  Alcotest.(check string) "nonzero index pointer" "/2"
    (pointer "nonzero index" (`List [ `Int 0; `Int 1; `String "\xff" ]));
  Alcotest.(check string) "three level pointer" "/0/a/1/0"
    (pointer "three levels"
       (`List [ `Assoc [ ("a", `List [ `Int 0; `List [ `String "\xff" ] ]) ] ]));
  Alcotest.(check string) "slash and tilde name pointer" "/a~1b~0c"
    (pointer "slash and tilde" (`Assoc [ ("a/b~c", `Variant ("v", None)) ]));
  Alcotest.(check string) "nan pointer" "/0/1"
    (pointer "nan" (`List [ `List [ `Int 0; `Float Float.nan ] ]));
  match
    Eta_schema_yojson.of_yojson
      (`List [ `Assoc [ ("ok", `Int 1); ("bad\xff", `Int 2) ] ])
  with
  | Error [ { path = [ Index 0; Field "bad\xff" ]; _ } ] -> ()
  | Error issues ->
      Alcotest.failf "unexpected object name issues: %s"
        (Eta_schema.render_issues issues)
  | Ok _ -> Alcotest.fail "expected object name rejection"

(* ^njson-fib9 ^njson-3ph9: ordinary schema decoding already supplies nested
   paths; adapter conversion success must not add a second prefix. *)
let test_schema_rejection_path_is_not_double_prefixed () =
  let schema = Eta_schema.array (Eta_schema.array Eta_schema.int) in
  match
    Eta_schema_yojson.decode_result schema
      (`List [ `List [ `Int 0; `String "bad" ] ])
  with
  | Ok _ -> Alcotest.fail "expected schema rejection"
  | Error issues ->
      Alcotest.(check int) "schema issue count" 1 (List.length issues);
      Alcotest.(check string) "schema pointer is not double prefixed" "/0/1"
        (Eta_schema.issue_to_json_pointer (List.hd issues))

(* ^njson-3ph9: the text the schema module renders is one JSON document that
   Yojson parses back to the same tree, escapes included. *)
let test_rendered_json_parses_back () =
  let tree =
    json_object
      [
        ("key\"\\", json_string "backslash \\ quote \"");
        ("controls", json_string "line\ncol\tcarriage\r\000");
        ("non_ascii", json_string "\xc3\xa9 \xf0\x9f\x98\x80 \xe4\xb8\xad");
      ]
  in
  let parsed =
    Eta_schema_yojson.of_yojson
      (Yojson.Safe.from_string (Eta_schema.Json.to_string tree))
  in
  match parsed with
  | Ok parsed ->
      Alcotest.(check bool) "escaped document parses back" true
        (Eta_schema.Json.equal tree parsed)
  | Error issues ->
      Alcotest.failf "rendered document did not parse back: %s"
        (Eta_schema.render_issues issues)

(* ^nschema-59sn: the encoder direction uses the same schema as the decoder and
   reports the field's pointer when it cannot encode a value. *)
type tab_state = Opened | Closed | Unknown

type tab = { id : string; state : tab_state }

let tab_state_schema =
  Eta_schema.enum ~name:"tab_state"
    [ ("open", Opened); ("closed", Closed) ]
    ~equal:( = )

let tab_schema =
  Eta_schema.record2 ~name:"tab"
    (fun id state -> { id; state })
    (Eta_schema.required "id" Eta_schema.string (fun tab -> tab.id))
    (Eta_schema.required "state" tab_state_schema (fun tab -> tab.state))
    ~equal:( = ) ()

let test_encode_direction () =
  let encoded = encode_ok ~name:"tab" tab_schema { id = "t_1"; state = Opened } in
  Alcotest.(check bool) "exact wire shape" true
    (Yojson.Safe.equal
       (`Assoc [ ("id", `String "t_1"); ("state", `String "open") ])
       encoded);
  (match
     Eta_schema_yojson.encode_result tab_schema { id = "t_1"; state = Unknown }
   with
  | Ok _ -> Alcotest.fail "expected an encode failure"
  | Error issues ->
      Alcotest.(check (list string)) "encode failure pointer" [ "/state" ]
        (List.map Eta_schema.issue_to_json_pointer issues));
  (* Decoding what the encoder produced round-trips. *)
  Alcotest.(check bool) "decode of the encoded value" true
    (match decode_ok ~name:"roundtrip" tab_schema encoded with
    | { id = "t_1"; state = Opened } -> true
    | _ -> false)

(* ^nschema-yyfu: the example request from Leash's docs/protocol.md, copied
   here verbatim (the ellipsis is U+2026). *)
type leash_args = { tab : string; index : int }
type leash_request = { v : int; owner : string; cmd : string; args : leash_args }

let leash_args_schema =
  Eta_schema.record2 ~name:"args"
    (fun tab index -> { tab; index })
    (Eta_schema.required "tab" Eta_schema.string (fun args -> args.tab))
    (Eta_schema.required "index" Eta_schema.int (fun args -> args.index))
    ~equal:( = ) ()

let leash_request_schema =
  Eta_schema.record4 ~name:"request"
    (fun v owner cmd args -> { v; owner; cmd; args })
    (Eta_schema.required "v" Eta_schema.int (fun request -> request.v))
    (Eta_schema.required "owner" Eta_schema.string (fun request -> request.owner))
    (Eta_schema.required "cmd" Eta_schema.string (fun request -> request.cmd))
    (Eta_schema.required "args" leash_args_schema (fun request -> request.args))
    ~equal:( = ) ()

let leash_example =
  {|{"v":1,"owner":"dsh:4f2a…","cmd":"click","args":{"tab":"t_9xk…","index":7}}|}

let test_leash_protocol_example () =
  let external_json = Yojson.Safe.from_string leash_example in
  let decoded = decode_ok ~name:"leash example" leash_request_schema external_json in
  Alcotest.(check int) "v" 1 decoded.v;
  Alcotest.(check string) "owner" "dsh:4f2a…" decoded.owner;
  Alcotest.(check string) "cmd" "click" decoded.cmd;
  Alcotest.(check string) "args.tab" "t_9xk…" decoded.args.tab;
  Alcotest.(check int) "args.index" 7 decoded.args.index;
  (* The same schema writes the request back, byte for byte. *)
  let encoded =
    encode_ok ~name:"leash example encode" leash_request_schema decoded
  in
  Alcotest.(check bool) "encode reproduces the example" true
    (Yojson.Safe.equal external_json encoded);
  (* A wrong-typed field names its pointer. *)
  let bad =
    Yojson.Safe.from_string
      {|{"v":1,"owner":"dsh:x","cmd":"click","args":{"tab":"t","index":"seven"}}|}
  in
  match Eta_schema_yojson.decode_result leash_request_schema bad with
  | Ok _ -> Alcotest.fail "expected a decode failure"
  | Error issues ->
      Alcotest.(check (list string)) "pointer of the wrong-typed field"
        [ "/args/index" ]
        (List.map Eta_schema.issue_to_json_pointer issues)

let () =
  Alcotest.run "eta_schema_yojson"
    [
      ( "adapter",
        [
          Alcotest.test_case "njson-35ih njson-3ph9 round trip" `Quick
            test_round_trip;
          Alcotest.test_case "njson-35ih malformed external data" `Quick
            test_reject_malformed_external_data;
          Alcotest.test_case "njson-35ih root adapter without open" `Quick
            test_root_adapter_without_open;
          Alcotest.test_case "njson-3ph9 large literal and serialization roundtrip"
            `Quick test_large_literal_and_serialization_roundtrip;
          Alcotest.test_case "njson-fib9 njson-3ph9 adapter issue paths" `Quick
            test_adapter_issue_paths;
          Alcotest.test_case
            "njson-fib9 njson-3ph9 schema rejection path is not double prefixed"
            `Quick test_schema_rejection_path_is_not_double_prefixed;
          Alcotest.test_case "njson-3ph9 rendered JSON parses back" `Quick
            test_rendered_json_parses_back;
          Alcotest.test_case "nschema-59sn encode direction" `Quick
            test_encode_direction;
          Alcotest.test_case "nschema-yyfu leash protocol example request" `Quick
            test_leash_protocol_example;
        ] );
    ]
