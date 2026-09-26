(* Tests for the ppx-yojson-minimal deriver (row 15).

   ^nppx-h4gz: [type ... [@@deriving yojson]] yields [yojson_of_t] and
   [t_of_yojson] on the 5.4.0+ox switch, where no ppxlib-based deriver
   installs. ^nppx-mao8: a record, a variant, an option, a list and a nested
   record round-trip, and a decode failure carries the offending subtree. *)

type tag_list = string list [@@deriving yojson]
(** An alias: converters delegate to the element converters. *)

type address = { city : string; zip : int; [@key "zipCode"] coords : float * float }
[@@deriving yojson]
(** A nested record with a renamed key and a tuple field. *)

(** Nullary constructors are strings; payload constructors are [tag, values] arrays. *)
type role = Admin | Member of string | Guest of int * bool [@@deriving yojson]

type unit_alias = unit [@@deriving yojson]

(* ^nderive-mmnx ^nderive-0wzg: optional fields are absent by default, with an
   explicit-null escape hatch. *)
type option_wire = { omitted : string option; retained : int option [@yojson.null] }
[@@deriving yojson]

(* ^nderive-fpd4: raw JSON is opaque to the deriver, even inside containers. *)
type raw_wire = { content : Yojson.Safe.t; pieces : Yojson.Safe.t list }
[@@deriving yojson]

(* ^nderive-q2om: nullary and payload constructors can both name their wire tag. *)
type renamed_wire =
  | With_human [@name "with_human"]
  | With_agent of string [@name "with_agent"]
  | With_both of string * int [@name "with_both"]
[@@deriving yojson]

(* ^nderive-qk91: OxCaml rejects [type t = {}], so unit is the single inhabitant. *)
type empty_args = unit [@@deriving yojson] [@@yojson.empty_record]

(** A recursive type exercises the [let rec] group. *)
type tree = Leaf of int | Node of tree * tree [@@deriving yojson]

type a = { b : b }

and b = { x : int } [@@deriving yojson]
(** A mutually recursive group becomes one [let rec ... and] chain. *)

type user = {
  name : string;
  age : int; [@default 0]
  nickname : string option;
  initial : char;
  tags : tag_list;
  scores : int array;
  alive : bool;
  ratio : float;
  home : address;
  role : role;
}
[@@deriving yojson]

let contains_substring needle haystack =
  let needle_len = String.length needle in
  let hay_len = String.length haystack in
  if needle_len = 0 then true
  else if needle_len > hay_len then false
  else
    let found = ref false in
    let i = ref 0 in
    while (not !found) && !i + needle_len <= hay_len do
      if String.sub haystack !i needle_len = needle then found := true;
      incr i
    done;
    !found

let expect_ok label = function
  | Ok value -> value
  | Error error -> Alcotest.failf "%s: unexpected error %s" label error

let expect_error_contains label needles = function
  | Ok _ -> Alcotest.failf "%s: expected an error result" label
  | Error error ->
      List.iter
        (fun needle ->
          if not (contains_substring needle error) then
            Alcotest.failf "%s: error %S does not contain %S" label error needle)
        needles

(* ^nppx-mao8 ^nppx-h4gz: the contract, case by case. *)

let home = { city = "Krakow"; zip = 30001; coords = (50.0, 19.9) }

let ada =
  {
    name = "ada";
    age = 36;
    nickname = Some "a0";
    initial = 'a';
    tags = [ "x"; "y" ];
    scores = [| 1; 2 |];
    alive = true;
    ratio = 0.5;
    home;
    role = Guest (1, true);
  }

let test_address_round_trip () =
  let back = expect_ok "address decodes" (address_of_yojson (yojson_of_address home)) in
  Alcotest.(check bool) "record round-trips" true (back = home)

let test_key_rename () =
  let text = Yojson.Safe.to_string (yojson_of_address home) in
  Alcotest.(check bool)
    "renamed key is encoded" true
    (contains_substring "\"zipCode\":30001" text);
  let back =
    expect_ok "renamed key decodes" (address_of_yojson (yojson_of_address home))
  in
  Alcotest.(check bool) "renamed key round-trips" true (back = home)

(* ^nderive-l1y6: exercise the actual generated converters, not just output text. *)
let test_option_omission () =
  let value = { omitted = None; retained = None } in
  let encoded = yojson_of_option_wire value in
  Alcotest.(check string)
    "None is omitted by default" "{\"retained\":null}"
    (Yojson.Safe.to_string encoded);
  List.iter
    (fun json ->
      let decoded =
        expect_ok "absent or null decodes as None" (option_wire_of_yojson json)
      in
      Alcotest.(check (option string)) "optional omitted" None decoded.omitted)
    [ encoded; `Assoc [ ("omitted", `Null); ("retained", `Null) ] ];
  let present = { omitted = Some "yes"; retained = Some 3 } in
  Alcotest.(check bool)
    "Some fields round-trip" true
    (expect_ok "option round-trip" (option_wire_of_yojson (yojson_of_option_wire present))
    = present)

let test_explicit_null () =
  let encoded = yojson_of_option_wire { omitted = None; retained = None } in
  Alcotest.(check bool)
    "explicit-null option is present" true
    (List.assoc_opt "retained" (match encoded with `Assoc fields -> fields | _ -> [])
    = Some `Null);
  let decoded = expect_ok "null decodes" (option_wire_of_yojson encoded) in
  Alcotest.(check (option int)) "explicit-null decodes as None" None decoded.retained

let test_raw_json_passthrough () =
  let content = `Assoc [ ("nested", `List [ `Null; `Bool true; `Int 4 ]) ] in
  let value = { content; pieces = [ `String "literal"; `Assoc [ ("x", `Int 7) ] ] } in
  let encoded = yojson_of_raw_wire value in
  Alcotest.(check string)
    "raw field unchanged"
    (Yojson.Safe.to_string content)
    (Yojson.Safe.to_string
       (match encoded with `Assoc fields -> List.assoc "content" fields | _ -> `Null));
  Alcotest.(check bool)
    "nested raw values round-trip" true
    (expect_ok "raw JSON decodes" (raw_wire_of_yojson encoded) = value)

let test_constructor_wire_names () =
  List.iter
    (fun (value, wire) ->
      Alcotest.(check string)
        "renamed tag encoded" wire
        (Yojson.Safe.to_string (yojson_of_renamed_wire value));
      Alcotest.(check bool)
        "renamed tag decodes" true
        (expect_ok "renamed tag" (renamed_wire_of_yojson (yojson_of_renamed_wire value))
        = value))
    [
      (With_human, "\"with_human\"");
      (With_agent "a", "[\"with_agent\",\"a\"]");
      (With_both ("b", 2), "[\"with_both\",\"b\",2]");
    ];
  expect_error_contains "unknown original constructor name"
    [ "renamed_wire"; "With_human" ]
    (renamed_wire_of_yojson (`String "With_human"))

let test_empty_object () =
  Alcotest.(check string)
    "empty arguments encode as object" "{}"
    (Yojson.Safe.to_string (yojson_of_empty_args ()));
  Alcotest.(check bool)
    "empty object decodes" true
    (expect_ok "empty arguments" (empty_args_of_yojson (`Assoc [])) = ());
  expect_error_contains "unknown empty-object key"
    [ "empty_args"; "unknown field"; "x" ]
    (empty_args_of_yojson (`Assoc [ ("x", `Int 1) ]));
  expect_error_contains "not null"
    [ "empty_args"; "expected object" ]
    (empty_args_of_yojson `Null)

let test_role_round_trip () =
  List.iter
    (fun role ->
      let back = expect_ok "role decodes" (role_of_yojson (yojson_of_role role)) in
      Alcotest.(check bool) "variant round-trips" true (back = role))
    [ Admin; Member "m"; Guest (1, true) ]

let test_user_round_trip () =
  let back = expect_ok "user decodes" (user_of_yojson (yojson_of_user ada)) in
  Alcotest.(check bool) "record, option, list, nested record round-trip" true (back = ada)

let test_recursive_round_trip () =
  let value = Node (Leaf 1, Node (Leaf 2, Leaf 3)) in
  let back = expect_ok "tree decodes" (tree_of_yojson (yojson_of_tree value)) in
  Alcotest.(check bool) "recursive type round-trips" true (back = value);
  let back =
    expect_ok "mutual group decodes" (a_of_yojson (yojson_of_a { b = { x = 7 } }))
  in
  Alcotest.(check bool)
    "mutually recursive group round-trips" true
    (back = { b = { x = 7 } })

let test_alias_round_trip () =
  let back =
    expect_ok "alias decodes" (tag_list_of_yojson (yojson_of_tag_list [ "a" ]))
  in
  Alcotest.(check (list string)) "alias round-trips" [ "a" ] back

let test_scalar_shapes () =
  Alcotest.(check string)
    "unit encodes as null" "null"
    (Yojson.Safe.to_string (yojson_of_unit_alias ()));
  Alcotest.(check bool)
    "unit decodes from null" true
    (expect_ok "unit decodes" (unit_alias_of_yojson `Null) = ());
  let back =
    expect_ok "user with initial decodes" (user_of_yojson (yojson_of_user ada))
  in
  Alcotest.(check char) "char round-trips" 'a' back.initial

let user_json fields = `Assoc fields

let base_fields () =
  [
    ("name", `String "x");
    ("nickname", `Null);
    ("tags", `List []);
    ("scores", `List []);
    ("alive", `Bool true);
    ("ratio", `Float 0.5);
    ("initial", `String "a");
    ("home", yojson_of_address home);
    ("role", `String "Admin");
  ]

let test_missing_field () =
  expect_error_contains "missing name"
    [ "user"; "missing field"; "name" ]
    (user_of_yojson (user_json (List.remove_assoc "name" (base_fields ()))));
  expect_error_contains "missing tags"
    [ "user"; "missing field"; "tags" ]
    (user_of_yojson (user_json (List.remove_assoc "tags" (base_fields ()))))

let test_wrong_type_carries_subtree () =
  let fields = ("age", `String "old") :: List.remove_assoc "age" (base_fields ()) in
  expect_error_contains "bad age"
    [ "user.age"; "expected int"; "\"old\"" ]
    (user_of_yojson (user_json fields))

let test_default_and_option () =
  let no_age = user_json (List.remove_assoc "age" (base_fields ())) in
  let back = expect_ok "missing age defaults" (user_of_yojson no_age) in
  Alcotest.(check int) "default applies" 0 back.age;
  Alcotest.(check (option string)) "missing option is None" None back.nickname;
  let explicit_null =
    user_json (("nickname", `String "a0") :: List.remove_assoc "nickname" (base_fields ()))
  in
  let back = expect_ok "present option decodes" (user_of_yojson explicit_null) in
  Alcotest.(check (option string)) "present option is Some" (Some "a0") back.nickname

let test_variant_rejects_unknown () =
  let fields = ("role", `String "Root") :: List.remove_assoc "role" (base_fields ()) in
  expect_error_contains "unknown constructor" [ "role"; "Root" ]
    (user_of_yojson (user_json fields))

let test_tuple_arity () =
  let bad_home =
    `Assoc
      [
        ("city", `String "c");
        ("zipCode", `Int 1);
        ("coords", `List [ `Float 1.0; `Float 2.0; `Float 3.0 ]);
      ]
  in
  expect_error_contains "tuple arity"
    [ "address.coords"; "array of 2" ]
    (address_of_yojson bad_home)

let test_list_index_path () =
  let fields =
    ("tags", `List [ `String "ok"; `Int 5 ]) :: List.remove_assoc "tags" (base_fields ())
  in
  expect_error_contains "list index"
    [ "user.tags"; "tag_list.[1]"; "5" ]
    (user_of_yojson (user_json fields))

let test_number_coercions () =
  let fields = ("ratio", `Int 2) :: List.remove_assoc "ratio" (base_fields ()) in
  let back = expect_ok "int decodes as float" (user_of_yojson (user_json fields)) in
  Alcotest.(check (float 0.0)) "int becomes float" 2.0 back.ratio;
  let big =
    ("age", `Intlit "99999999999999999999999") :: List.remove_assoc "age" (base_fields ())
  in
  expect_error_contains "overflowing int"
    [ "user.age"; "expected int" ]
    (user_of_yojson (user_json big))

(* ^nnoschema-zi2m: a record decoder refuses an object field the type does not name —
   an unknown key is a typo in a config file or a request — and reports the path and the
   key. A declaration that carries [@@yojson.allow_extra_fields] opts out and ignores
   what it does not know, which is what a shape we do not own needs. *)
type strict_record = { kept : int } [@@deriving yojson]
type tolerant_record = { kept : int } [@@deriving yojson] [@@yojson.allow_extra_fields]
type wrapper = { inner : strict_record } [@@deriving yojson]

let test_unknown_fields () =
  let known = `Assoc [ ("kept", `Int 1) ] in
  let extra = `Assoc [ ("kept", `Int 1); ("surprise", `Bool true) ] in
  Alcotest.(check bool)
    "a document with only known fields decodes" true
    (Result.is_ok (strict_record_of_yojson known));
  expect_error_contains "unknown field refused"
    [ "strict_record"; "unknown field"; "surprise" ]
    (strict_record_of_yojson extra);
  (* The opt-out is per declaration: a tolerant record ignores the same key ... *)
  (match tolerant_record_of_yojson extra with
  | Ok { kept = 1 } -> ()
  | Ok _ -> Alcotest.fail "the tolerant record keeps the known field"
  | Error message -> Alcotest.failf "allow_extra_fields accepts: %s" message);
  (* ... while a record that merely refers to it is strict about its own fields. *)
  expect_error_contains "the outer record still refuses"
    [ "wrapper"; "unknown field"; "surprise" ]
    (wrapper_of_yojson (`Assoc [ ("inner", extra); ("surprise", `Int 2) ]));
  expect_error_contains "a nested record reports its own path"
    [ "wrapper.inner"; "unknown field"; "surprise" ]
    (wrapper_of_yojson (`Assoc [ ("inner", extra) ]))

(* ^nnoschema-ifg0: a field whose type lives in another module is written with its
   own converters. A qualified name may be several modules deep, which is how a
   config record names its secret's type without opening the package that owns
   it. The [Mark] module stands in for [Eta_observability.Redact]. *)
module Mark = struct
  type t = string

  let yojson_of_t value = `String value

  let t_of_yojson = function
    | `String value -> Ok value
    | json -> Error ("mark: expected string, got " ^ Yojson.Safe.to_string json)
end

type marked = { mark : Mark.t; nested : Mark.t list } [@@deriving yojson]

let test_qualified_module_path () =
  let value = { mark = "a"; nested = [ "b" ] } in
  let back =
    expect_ok "qualified field decodes" (marked_of_yojson (yojson_of_marked value))
  in
  Alcotest.(check bool) "the qualified converters round-trip" true (back = value);
  expect_error_contains "qualified failure"
    [ "marked.mark"; "mark:"; "7" ]
    (marked_of_yojson (`Assoc [ ("mark", `Int 7); ("nested", `List []) ]))

(* ^nppx-mao8: the preprocessor itself is pinned as a pure function. *)

let process filename source = Ppx_yojson_minimal.Derive.process ~filename ~source

let test_passthrough () =
  let source = "let answer = 41 + 1\n" in
  Alcotest.(check string)
    "no deriving is byte-identical" source
    (expect_ok "passthrough" (process "a.ml" source))

let test_syntax_error_passes_through () =
  let source = "let = \n" in
  Alcotest.(check string)
    "the compiler reports syntax" source
    (expect_ok "syntax" (process "a.ml" source))

let index_of_substring needle haystack =
  let needle_len = String.length needle in
  let hay_len = String.length haystack in
  let found = ref None in
  let i = ref 0 in
  while Option.is_none !found && !i + needle_len <= hay_len do
    if String.sub haystack !i needle_len = needle then found := Some !i;
    incr i
  done;
  match !found with
  | Some i -> i
  | None -> Alcotest.failf "expected output to contain %S" needle

let test_insertion_is_in_place () =
  let source = "type t = { x : int } [@@deriving yojson]\nlet after = 1\n" in
  let output = expect_ok "derives" (process "a.ml" source) in
  Alcotest.(check bool)
    "converters are generated" true
    (contains_substring "yojson_of_t" output);
  Alcotest.(check bool)
    "the attribute is blanked" false
    (contains_substring "[@@deriving yojson]" output);
  Alcotest.(check bool)
    "converters come before the code that follows" true
    (index_of_substring "yojson_of_t" output < index_of_substring "let after" output)

let test_typo_is_loud () =
  let source = "type t = int [@@deriving yosjon]\n" in
  expect_error_contains "typo" [ "yosjon" ] (process "a.ml" source)

let test_other_deriver_is_loud () =
  let source = "type t = int [@@deriving show]\n" in
  expect_error_contains "other deriver" [ "show" ] (process "a.ml" source)

let test_unsupported_shapes_are_loud () =
  let tick = String.make 1 (Char.chr 39) in
  let cases =
    [
      ( "polymorphic variant",
        "not supported",
        "type t = [ `A | `B ] [@@deriving yojson]\n" );
      ( "type parameter",
        "type parameters",
        "type " ^ tick ^ "a t = " ^ tick ^ "a list [@@deriving yojson]\n" );
      ("function", "not supported", "type t = int -> int [@@deriving yojson]\n");
      ("abstract", "abstract", "type t [@@deriving yojson]\n");
      ( "explicit-null only on option",
        "requires an option type",
        "type t = { x : int [@yojson.null] } [@@deriving yojson]\n" );
      ( "bad constructor wire name",
        "expects a string literal",
        "type t = A [@name 3] [@@deriving yojson]\n" );
      ( "duplicate constructor wire names",
        "duplicate variant wire name",
        "type t = A [@name \"same\"] | B [@name \"same\"] [@@deriving yojson]\n" );
      ( "empty record marker on non-unit",
        "requires a unit alias",
        "type t = int [@@deriving yojson] [@@yojson.empty_record]\n" );
      ( "empty record does not allow extra fields",
        "cannot allow extra fields",
        "type t = unit [@@deriving yojson] [@@yojson.empty_record] \
         [@@yojson.allow_extra_fields]\n" );
      ( "nested module",
        "below the top level",
        "module M = struct\n  type t = int [@@deriving yojson]\nend\n" );
      ("value attribute", "type declarations", "let x = 1 [@@deriving yojson]\n");
      ( "nested value attribute",
        "type declarations",
        "module M = struct\n  let x = 1 [@@deriving yojson]\nend\n" );
    ]
  in
  List.iter
    (fun (label, needle, source) ->
      expect_error_contains label [ needle ] (process "a.ml" source))
    cases

let test_interface_generates_vals () =
  let source = "type t = { x : int } [@@deriving yojson]\n" in
  let output = expect_ok "interface derives" (process "a.mli" source) in
  Alcotest.(check bool)
    "encoder val" true
    (contains_substring "val yojson_of_t : t -> Yojson.Safe.t" output);
  Alcotest.(check bool) "decoder val" true (contains_substring "val t_of_yojson" output)

let () =
  Alcotest.run "ppx_yojson_minimal"
    [
      ( "deriving",
        [
          Alcotest.test_case "nppx-mao8 nppx-h4gz record round-trips" `Quick
            test_address_round_trip;
          Alcotest.test_case "nppx-mao8 key rename" `Quick test_key_rename;
          Alcotest.test_case "nderive-mmnx nderive-l1y6 option omission" `Quick
            test_option_omission;
          Alcotest.test_case "nderive-0wzg nderive-l1y6 explicit null" `Quick
            test_explicit_null;
          Alcotest.test_case "nderive-fpd4 nderive-l1y6 raw JSON" `Quick
            test_raw_json_passthrough;
          Alcotest.test_case "nderive-q2om nderive-l1y6 wire constructor names" `Quick
            test_constructor_wire_names;
          Alcotest.test_case "nderive-qk91 nderive-l1y6 empty object" `Quick
            test_empty_object;
          Alcotest.test_case "nppx-mao8 variant round-trips" `Quick test_role_round_trip;
          Alcotest.test_case "nppx-mao8 nested record round-trips" `Quick
            test_user_round_trip;
          Alcotest.test_case "nppx-mao8 alias round-trips" `Quick test_alias_round_trip;
          Alcotest.test_case "nppx-h4gz recursive types round-trip" `Quick
            test_recursive_round_trip;
          Alcotest.test_case "nppx-h4gz scalar shapes" `Quick test_scalar_shapes;
          Alcotest.test_case "nppx-mao8 missing field" `Quick test_missing_field;
          Alcotest.test_case "nppx-mao8 failure carries the subtree" `Quick
            test_wrong_type_carries_subtree;
          Alcotest.test_case "nppx-mao8 default and option" `Quick test_default_and_option;
          Alcotest.test_case "nppx-mao8 unknown constructor" `Quick
            test_variant_rejects_unknown;
          Alcotest.test_case "nppx-mao8 tuple arity" `Quick test_tuple_arity;
          Alcotest.test_case "nppx-mao8 list index path" `Quick test_list_index_path;
          Alcotest.test_case "nppx-mao8 number coercions" `Quick test_number_coercions;
          Alcotest.test_case "nppx-h4gz ^nnoschema-ifg0 qualified module path" `Quick
            test_qualified_module_path;
          Alcotest.test_case "nppx-h4gz ^nnoschema-zi2m unknown fields" `Quick
            test_unknown_fields;
        ] );
      ( "preprocessor",
        [
          Alcotest.test_case "nppx-mao8 passthrough is identical" `Quick test_passthrough;
          Alcotest.test_case "nppx-mao8 syntax passes through" `Quick
            test_syntax_error_passes_through;
          Alcotest.test_case "nppx-mao8 insertion is in place" `Quick
            test_insertion_is_in_place;
          Alcotest.test_case "nppx-h4gz typo is loud" `Quick test_typo_is_loud;
          Alcotest.test_case "nppx-h4gz other deriver is loud" `Quick
            test_other_deriver_is_loud;
          Alcotest.test_case "nppx-h4gz unsupported shapes are loud" `Quick
            test_unsupported_shapes_are_loud;
          Alcotest.test_case "nppx-h4gz interface generates vals" `Quick
            test_interface_generates_vals;
        ] );
    ]
