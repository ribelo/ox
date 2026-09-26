open Eta_schema

(* Local helpers for the pure schema surface. The schema package has no test
   helper library of its own, and these tests use alcotest only. *)

let json_testable =
  Alcotest.testable
    (fun fmt json -> Format.pp_print_string fmt (Json.to_string json))
    Json.equal

let issue_testable =
  Alcotest.testable
    (fun fmt issue -> Format.pp_print_string fmt (render_issue issue))
    ( = )

let issues_testable = Alcotest.list issue_testable

let fail_issues name kind issues =
  Alcotest.failf "%s: %s: %s" name kind (render_issues issues)

let expect_result_ok name kind = function
  | Ok value -> value
  | Error issues -> fail_issues name kind issues

let expect_ok ?(name = "schema") = function
  | Ok value -> value
  | Error issues -> fail_issues name "failed" issues

let expect_decode_error ?(name = "schema") = function
  | Ok _ -> Alcotest.failf "%s: expected decode failure" name
  | Error issues -> issues

let expect_encode_error ?(name = "schema") = function
  | Ok _ -> Alcotest.failf "%s: expected encode failure" name
  | Error issues -> issues

let decode_ok ?(name = "decode") schema value =
  expect_result_ok name "decode failed" (decode_result schema value)

let encode_ok ?(name = "encode") schema value =
  expect_result_ok name "encode failed" (encode_result schema value)

let check_decode testable ?(name = "decode") schema json expected =
  Alcotest.check testable name expected (decode_ok ~name schema json)

let check_encode ?(name = "encode") schema value expected =
  Alcotest.check json_testable name expected (encode_ok ~name schema value)

let check_roundtrip_json ?(name = "roundtrip") schema json_value =
  let decoded = decode_ok ~name schema json_value in
  Alcotest.check json_testable name json_value (encode_ok ~name schema decoded)

(* Checked-construction helpers for fixtures whose inputs are known valid. *)
let construction_ok ~name = function
  | Ok json -> json
  | Error issues ->
      Alcotest.failf "%s: invalid JSON construction: %s" name (render_issues issues)

let json_string value = construction_ok ~name:"json_string" (Json.string value)
let json_number value = construction_ok ~name:"json_number" (Json.number value)
let json_intlit value = construction_ok ~name:"json_intlit" (Json.intlit value)
let json_object fields = construction_ok ~name:"json_object" (Json.object_ fields)

module User_id : sig
  type t = private string

  val schema : t Eta_schema.t
  val value : t -> string
  val equal : t -> t -> bool
end = struct
  type t = string

  let valid s = String.length s > 4 && String.sub s 0 4 = "usr_"
  let value s = s
  let equal = String.equal

  let schema =
    Eta_schema.transform ~name:"user_id"
      ~decode:(fun s -> if valid s then Ok s else Error [ issue "Expected user_id" ])
      ~encode:value ~equal Eta_schema.string
end

module Email : sig
  type t = private string

  val schema : t Eta_schema.t
  val value : t -> string
  val equal : t -> t -> bool
end = struct
  type t = string

  let valid s = String.contains s '@'
  let value s = s
  let equal = String.equal

  let schema =
    Eta_schema.transform ~name:"email"
      ~decode:(fun s -> if valid s then Ok s else Error [ issue "Expected email" ])
      ~encode:value ~equal Eta_schema.string
end

module Flag_key : sig
  type t = private string

  val schema : t Eta_schema.t
  val value : t -> string
  val equal : t -> t -> bool
end = struct
  type t = string

  let valid s = String.length s > 5 && String.sub s 0 5 = "flag."
  let value s = s
  let equal = String.equal

  let schema =
    Eta_schema.transform ~name:"flag_key"
      ~decode:(fun s -> if valid s then Ok s else Error [ issue "Expected flag_key" ])
      ~encode:value ~equal Eta_schema.string
end

type user_id = User_id.t
type email = Email.t
type flag_key = Flag_key.t
type role = Admin | Analyst | Viewer
type user = { id : user_id; name : string; email : email option; roles : role list }
type database = { host : string; port : int; ssl : bool }

type auth =
  | Password of { min_length : int }
  | OAuth of { issuer : string; client_id : string }

type feature = { key : flag_key; enabled : bool; rollout : int option }

type config = {
  service : string;
  db : database;
  auth : auth;
  users : user list;
  features : feature list;
  retry_after_ms : int;
}

type event =
  | User_created of user
  | Feature_toggled of { key : flag_key; enabled : bool }
  | Metric of { name : string; value : float }

type menu =
  | Item of { label : string; route : string }
  | Group of { label : string; children : menu list }

let role_equal a b =
  match (a, b) with
  | Admin, Admin | Analyst, Analyst | Viewer, Viewer -> true
  | _ -> false

let user_equal a b =
  User_id.equal a.id b.id && String.equal a.name b.name
  && Option.equal Email.equal a.email b.email
  && List.equal role_equal a.roles b.roles

let database_equal a b =
  String.equal a.host b.host && Int.equal a.port b.port && Bool.equal a.ssl b.ssl

let auth_equal a b =
  match (a, b) with
  | Password a, Password b -> Int.equal a.min_length b.min_length
  | OAuth a, OAuth b ->
      String.equal a.issuer b.issuer && String.equal a.client_id b.client_id
  | _ -> false

let feature_equal a b =
  Flag_key.equal a.key b.key
  && Bool.equal a.enabled b.enabled
  && Option.equal Int.equal a.rollout b.rollout

let config_equal a b =
  String.equal a.service b.service
  && database_equal a.db b.db && auth_equal a.auth b.auth
  && List.equal user_equal a.users b.users
  && List.equal feature_equal a.features b.features
  && Int.equal a.retry_after_ms b.retry_after_ms

let event_equal a b =
  match (a, b) with
  | User_created a, User_created b -> user_equal a b
  | Feature_toggled a, Feature_toggled b ->
      Flag_key.equal a.key b.key && Bool.equal a.enabled b.enabled
  | Metric a, Metric b -> String.equal a.name b.name && Float.equal a.value b.value
  | _ -> false

let rec menu_equal a b =
  match (a, b) with
  | Item a, Item b -> String.equal a.label b.label && String.equal a.route b.route
  | Group a, Group b ->
      String.equal a.label b.label && List.equal menu_equal a.children b.children
  | _ -> false

let non_empty =
  Eta_schema.refine ~name:"non-empty"
    (fun s -> if String.length s > 0 then [] else [ issue "Expected non-empty string" ])
    Eta_schema.string

let bounded_int ~min ~max =
  Eta_schema.refine
    ~name:(Printf.sprintf "%d..%d" min max)
    (fun n ->
      if n >= min && n <= max then []
      else [ issue (Printf.sprintf "Expected %d <= value <= %d" min max) ])
    Eta_schema.int

let role =
  Eta_schema.enum ~name:"role"
    [ ("admin", Admin); ("analyst", Analyst); ("viewer", Viewer) ]
    ~equal:role_equal

let retry_after =
  Eta_schema.transform ~name:"duration-ms"
    ~decode:(fun s ->
      if String.ends_with ~suffix:"ms" s then
        match int_of_string_opt (String.sub s 0 (String.length s - 2)) with
        | Some n when n >= 0 -> Ok n
        | _ -> Error [ issue "Expected non-negative duration in ms" ]
      else Error [ issue "Expected duration like 500ms" ])
    ~encode:(fun n -> string_of_int n ^ "ms")
    ~equal:Int.equal Eta_schema.string

let database =
  Eta_schema.record3 ~name:"database"
    (fun host port ssl -> { host; port; ssl })
    (Eta_schema.required "host" non_empty (fun db -> db.host))
    (Eta_schema.required "port" (bounded_int ~min:1 ~max:65535) (fun db -> db.port))
    (Eta_schema.required "ssl" Eta_schema.bool (fun db -> db.ssl))
    ~equal:database_equal ()

let user =
  Eta_schema.record4 ~name:"user"
    (fun id name email roles -> { id; name; email; roles })
    (Eta_schema.required "id" User_id.schema (fun u -> u.id))
    (Eta_schema.required "name" non_empty (fun u -> u.name))
    (Eta_schema.optional "email" Email.schema (fun u -> u.email))
    (Eta_schema.required "roles" (Eta_schema.array role) (fun u -> u.roles))
    ~equal:user_equal ()

let feature =
  Eta_schema.record3 ~name:"feature"
    (fun key enabled rollout -> { key; enabled; rollout })
    (Eta_schema.required "key" Flag_key.schema (fun f -> f.key))
    (Eta_schema.required "enabled" Eta_schema.bool (fun f -> f.enabled))
    (Eta_schema.optional "rollout" (bounded_int ~min:0 ~max:100) (fun f -> f.rollout))
    ~equal:feature_equal ()

let auth =
  let password_decode json =
    match Json.find "minLength" json with
    | Some value -> (
        match Eta_schema.decode_result (bounded_int ~min:8 ~max:128) value with
        | Ok min_length -> Ok (Password { min_length })
        | Error issues -> Error (at_field "minLength" issues))
    | None -> Error [ issue ~path:[ Field "minLength" ] "Missing key" ]
  in
  let oauth_decode json =
    match (Json.find "issuer" json, Json.find "clientId" json) with
    | Some issuer_json, Some client_json -> (
        match
          ( Eta_schema.decode_result non_empty issuer_json,
            Eta_schema.decode_result non_empty client_json )
        with
        | Ok issuer, Ok client_id -> Ok (OAuth { issuer; client_id })
        | a, b ->
            let collect = function Ok _ -> [] | Error issues -> issues in
            Error (at_field "issuer" (collect a) @ at_field "clientId" (collect b)))
    | _ -> Error [ issue "Invalid OAuth auth" ]
  in
  let password_encode = function
    | Password { min_length } ->
        Ok (Some (json_object [ ("minLength", Json.int min_length) ]))
    | _ -> Ok None
  in
  let oauth_encode = function
    | OAuth { issuer; client_id } ->
        Ok
          (Some
             (json_object
                [ ("issuer", json_string issuer); ("clientId", json_string client_id) ]))
    | _ -> Ok None
  in
  Eta_schema.tagged_union ~name:"auth" ~tag:"_tag"
    [
      Eta_schema.case ~tag:"Password" ~decode:password_decode ~encode:password_encode;
      Eta_schema.case ~tag:"OAuth" ~decode:oauth_decode ~encode:oauth_encode;
    ]
    ~equal:auth_equal

let config =
  Eta_schema.record6 ~name:"config"
    (fun service db auth users features retry_after_ms ->
      { service; db; auth; users; features; retry_after_ms })
    (Eta_schema.required "service" non_empty (fun c -> c.service))
    (Eta_schema.required "db" database (fun c -> c.db))
    (Eta_schema.required "auth" auth (fun c -> c.auth))
    (Eta_schema.required "users" (Eta_schema.array user) (fun c -> c.users))
    (Eta_schema.required "features" (Eta_schema.array feature) (fun c -> c.features))
    (Eta_schema.required "retryAfter" retry_after (fun c -> c.retry_after_ms))
    ~equal:config_equal ()

let event =
  let user_created_decode json =
    match Json.find "user" json with
    | Some value ->
        Result.map (fun user -> User_created user) (Eta_schema.decode_result user value)
    | None -> Error [ issue ~path:[ Field "user" ] "Missing key" ]
  in
  let user_created_encode = function
    | User_created u ->
        Result.map
          (fun user_json -> Some (json_object [ ("user", user_json) ]))
          (Eta_schema.encode_result user u)
    | _ -> Ok None
  in
  let feature_toggled_decode json =
    match (Json.find "key" json, Json.find "enabled" json) with
    | Some key_json, Some enabled_json -> (
        match
          ( Eta_schema.decode_result Flag_key.schema key_json,
            Eta_schema.decode_result Eta_schema.bool enabled_json )
        with
        | Ok key, Ok enabled -> Ok (Feature_toggled { key; enabled })
        | a, b ->
            let collect = function Ok _ -> [] | Error issues -> issues in
            Error (at_field "key" (collect a) @ at_field "enabled" (collect b)))
    | _ -> Error [ issue "Invalid FeatureToggled event" ]
  in
  let feature_toggled_encode = function
    | Feature_toggled { key; enabled } ->
        Result.map
          (fun key_json ->
            Some (json_object [ ("key", key_json); ("enabled", Json.bool enabled) ]))
          (Eta_schema.encode_result Flag_key.schema key)
    | _ -> Ok None
  in
  let metric_decode json =
    match (Json.find "name" json, Json.find "value" json) with
    | Some (Json.String name), Some value_json -> (
        match Eta_schema.decode_result Eta_schema.float value_json with
        | Ok value -> Ok (Metric { name; value })
        | Error issues -> Error (at_field "value" issues))
    | _ -> Error [ issue "Invalid Metric event" ]
  in
  let metric_encode = function
    | Metric { name; value } ->
        Ok
          (Some (json_object [ ("name", json_string name); ("value", json_number value) ]))
    | _ -> Ok None
  in
  Eta_schema.tagged_union ~name:"event" ~tag:"_tag"
    [
      Eta_schema.case ~tag:"UserCreated" ~decode:user_created_decode
        ~encode:user_created_encode;
      Eta_schema.case ~tag:"FeatureToggled" ~decode:feature_toggled_decode
        ~encode:feature_toggled_encode;
      Eta_schema.case ~tag:"Metric" ~decode:metric_decode ~encode:metric_encode;
    ]
    ~equal:event_equal

let rec menu () =
  let item_decode json =
    match (Json.find "label" json, Json.find "route" json) with
    | Some (Json.String label), Some (Json.String route) -> Ok (Item { label; route })
    | _ -> Error [ issue "Invalid menu item" ]
  in
  let item_encode = function
    | Item { label; route } ->
        Ok
          (Some
             (json_object [ ("label", json_string label); ("route", json_string route) ]))
    | _ -> Ok None
  in
  let group_decode json =
    match (Json.find "label" json, Json.find "children" json) with
    | Some (Json.String label), Some children_json -> (
        match
          Eta_schema.decode_result
            (Eta_schema.array (Eta_schema.lazy_ menu))
            children_json
        with
        | Ok children -> Ok (Group { label; children })
        | Error issues -> Error (at_field "children" issues))
    | _ -> Error [ issue "Invalid menu group" ]
  in
  let group_encode = function
    | Group { label; children } ->
        Result.map
          (fun children_json ->
            Some
              (json_object [ ("label", json_string label); ("children", children_json) ]))
          (Eta_schema.encode_result (Eta_schema.array (Eta_schema.lazy_ menu)) children)
    | _ -> Ok None
  in
  Eta_schema.tagged_union ~name:"menu" ~tag:"_tag"
    [
      Eta_schema.case ~tag:"Item" ~decode:item_decode ~encode:item_encode;
      Eta_schema.case ~tag:"Group" ~decode:group_decode ~encode:group_encode;
    ]
    ~equal:menu_equal

let sample_user_json =
  json_object
    [
      ("id", json_string "usr_123");
      ("name", json_string "Ada");
      ("email", json_string "ada@example.test");
      ("roles", Json.array [ json_string "admin"; json_string "analyst" ]);
    ]

let sample_config_json =
  json_object
    [
      ("service", json_string "billing");
      ( "db",
        json_object
          [
            ("host", json_string "db.internal");
            ("port", Json.int 5432);
            ("ssl", Json.bool true);
          ] );
      ( "auth",
        json_object
          [
            ("_tag", json_string "OAuth");
            ("issuer", json_string "https://issuer.example");
            ("clientId", json_string "billing-web");
          ] );
      ("users", Json.array [ sample_user_json ]);
      ( "features",
        Json.array
          [
            json_object
              [
                ("key", json_string "flag.new-checkout");
                ("enabled", Json.bool true);
                ("rollout", Json.int 25);
              ];
          ] );
      ("retryAfter", json_string "500ms");
    ]

let bad_config_json =
  json_object
    [
      ("service", json_string "");
      ( "db",
        json_object
          [
            ("host", json_string ""); ("port", Json.int 70000); ("ssl", json_string "yes");
          ] );
      ("auth", json_object [ ("_tag", json_string "Unknown") ]);
      ("users", Json.array [ json_object [ ("id", json_string "bad") ] ]);
      ( "features",
        Json.array
          [
            json_object
              [
                ("key", json_string "bad");
                ("enabled", Json.bool true);
                ("rollout", Json.int 200);
              ];
          ] );
      ("retryAfter", json_string "soon");
    ]

let sample_event_json =
  json_object [ ("_tag", json_string "UserCreated"); ("user", sample_user_json) ]

let sample_menu_json =
  json_object
    [
      ("_tag", json_string "Group");
      ("label", json_string "root");
      ( "children",
        Json.array
          [
            json_object
              [
                ("_tag", json_string "Item");
                ("label", json_string "Home");
                ("route", json_string "/");
              ];
            json_object
              [
                ("_tag", json_string "Group");
                ("label", json_string "Admin");
                ( "children",
                  Json.array
                    [
                      json_object
                        [
                          ("_tag", json_string "Item");
                          ("label", json_string "Users");
                          ("route", json_string "/admin/users");
                        ];
                    ] );
              ];
          ] );
    ]

let check_bool name value = if not value then failwith name
let check_int name expected actual = if expected <> actual then failwith name

let check_string name expected actual =
  if not (String.equal expected actual) then failwith name

let check_option_string name expected actual =
  match (expected, actual) with
  | None, None -> ()
  | Some expected, Some actual when String.equal expected actual -> ()
  | _ -> failwith name

let test_config_roundtrip () =
  let decoded = decode_ok config sample_config_json in
  check_bool "retry transform" (decoded.retry_after_ms = 500);
  check_bool "feature key value"
    (String.equal "flag.new-checkout" (Flag_key.value (List.hd decoded.features).key));
  check_bool "roundtrip json" (Json.equal sample_config_json (encode_ok config decoded));
  check_bool "self equal" (Eta_schema.equal config decoded decoded)

let test_many_issues () =
  let issues =
    Eta_schema.decode_result config bad_config_json
    |> expect_decode_error ~name:"bad config"
  in
  check_bool "all errors" (List.length issues >= 8);
  check_bool "nested user id path"
    (List.exists
       (fun issue -> issue.path = [ Field "users"; Index 0; Field "id" ])
       issues)

let test_tagged_and_recursive () =
  let event_value = decode_ok event sample_event_json in
  check_bool "event self equal" (Eta_schema.equal event event_value event_value);
  check_bool "event roundtrip"
    (Json.equal sample_event_json (encode_ok event event_value));
  let menu_value = decode_ok (menu ()) sample_menu_json in
  check_bool "menu self equal" (Eta_schema.equal (menu ()) menu_value menu_value);
  check_bool "menu roundtrip"
    (Json.equal sample_menu_json (encode_ok (menu ()) menu_value))

let test_issue_paths_distinguish_fields_and_indexes () =
  let issues =
    Eta_schema.decode_result config bad_config_json
    |> expect_decode_error ~name:"bad config"
  in
  let user_id_issue =
    match
      List.find_opt
        (fun issue -> issue.path = [ Field "users"; Index 0; Field "id" ])
        issues
    with
    | Some issue -> issue
    | None -> failwith "expected nested user id issue"
  in
  check_string "rendered path" "user_id: Expected user_id at users[0].id"
    (render_issue user_id_issue);
  check_option_string "source schema" (Some "user_id") user_id_issue.schema_name;
  (match user_id_issue.kind with
  | Custom message -> check_string "custom issue" "Expected user_id" message
  | _ -> failwith "expected custom issue");
  check_string "json pointer" "/users/0/id" (issue_to_json_pointer user_id_issue);
  let numeric_key_issue =
    issue ~path:[ Field "users"; Field "0"; Field "id" ] "field key"
  in
  check_string "numeric field path" "field key at users.0.id"
    (render_issue numeric_key_issue)

type named_name = { name : string }

let named_name_equal a b = String.equal a.name b.name

let named_schema schema_name =
  Eta_schema.record1 ~name:schema_name
    (fun name -> { name })
    (Eta_schema.required "name" Eta_schema.string (fun value -> value.name))
    ~equal:named_name_equal ()

let test_issue_source_discriminator () =
  let json = json_object [ ("name", Json.int 42) ] in
  let user_issues =
    Eta_schema.decode_result (named_schema "user") json
    |> expect_decode_error ~name:"user"
  in
  let admin_issues =
    Eta_schema.decode_result (named_schema "admin") json
    |> expect_decode_error ~name:"admin"
  in
  let user_issue = List.hd user_issues in
  let admin_issue = List.hd admin_issues in
  check_option_string "user source" (Some "user") user_issue.schema_name;
  check_option_string "admin source" (Some "admin") admin_issue.schema_name;
  (match user_issue.kind with
  | Type_mismatch { expected; got } ->
      check_string "expected string" "string" expected;
      check_string "got int" "42" got
  | _ -> failwith "expected type mismatch");
  check_string "source render" "user: Expected string, got 42 at name"
    (render_issue user_issue)

let test_json_number_rendering () =
  check_string "integer float has no trailing dot" "1" (Json.to_string (json_number 1.));
  check_string "fractional float" "1.5" (Json.to_string (json_number 1.5));
  check_string "large integral float does not overflow" "1e+100"
    (Json.to_string (json_number 1e100));
  check_string "large int literal stays exact" "9007199254740993"
    (Json.to_string (json_intlit "9007199254740993"));
  ignore
    (Eta_schema.decode_result Eta_schema.int (json_number 1e100)
    |> expect_decode_error ~name:"large integer")

(* Minimal reader for the JSON string literal this library writes: enough to
   prove the escaping is reversible without adding a JSON dependency to the
   stdlib-only package's tests. *)
let unescape_json_string rendered =
  let length = String.length rendered in
  if
    length < 2
    || (not (Char.equal rendered.[0] '"'))
    || not (Char.equal rendered.[length - 1] '"')
  then failwith "not a JSON string literal";
  let buffer = Buffer.create length in
  let hex c =
    if c >= '0' && c <= '9' then Char.code c - Char.code '0'
    else if c >= 'a' && c <= 'f' then Char.code c - Char.code 'a' + 10
    else if c >= 'A' && c <= 'F' then Char.code c - Char.code 'A' + 10
    else failwith "bad hex digit"
  in
  let rec loop index =
    if index >= length - 1 then ()
    else
      match rendered.[index] with
      | '\\' -> (
          match rendered.[index + 1] with
          | '"' ->
              Buffer.add_char buffer '"';
              loop (index + 2)
          | '\\' ->
              Buffer.add_char buffer '\\';
              loop (index + 2)
          | 'b' ->
              Buffer.add_char buffer '\b';
              loop (index + 2)
          | 'f' ->
              Buffer.add_char buffer '\012';
              loop (index + 2)
          | 'n' ->
              Buffer.add_char buffer '\n';
              loop (index + 2)
          | 'r' ->
              Buffer.add_char buffer '\r';
              loop (index + 2)
          | 't' ->
              Buffer.add_char buffer '\t';
              loop (index + 2)
          | 'u' ->
              let code = (hex rendered.[index + 2] * 16) + hex rendered.[index + 3] in
              Buffer.add_char buffer (Char.chr code);
              loop (index + 6)
          | _ -> failwith "unknown escape")
      | c ->
          Buffer.add_char buffer c;
          loop (index + 1)
  in
  loop 1;
  Buffer.contents buffer

let check_json_string_roundtrip name value =
  check_string name value (unescape_json_string (Json.to_string (json_string value)))

let test_json_string_rendering () =
  let quote_backslash = "backslash \\ quote \"" in
  check_string "quote and backslash escaping" "\"backslash \\\\ quote \\\"\""
    (Json.to_string (json_string quote_backslash));
  check_json_string_roundtrip "quote and backslash roundtrip" quote_backslash;
  let controls = "line\ncol\tcarriage\rbackspace\bform\012nul\000" in
  check_string "control escaping"
    "\"line\\ncol\\tcarriage\\rbackspace\\bform\\fnul\\u0000\""
    (Json.to_string (json_string controls));
  check_json_string_roundtrip "control roundtrip" controls;
  let non_ascii = "é 😀 中" in
  check_string "non-ascii stays utf8"
    ("\"" ^ non_ascii ^ "\"")
    (Json.to_string (json_string non_ascii));
  check_json_string_roundtrip "non-ascii roundtrip" non_ascii;
  let separators = "line\226\128\168para\226\128\169end" in
  check_string "line separators stay utf8"
    ("\"" ^ separators ^ "\"")
    (Json.to_string (json_string separators));
  check_json_string_roundtrip "line separators roundtrip" separators
(* The rendered text of a document with nasty escaping is parsed back by the
     Yojson bridge in test/schema_yojson, where the JSON dependency lives. *)

type request_user = { request_id : user_id }
type canonical_user = { canonical_id : user_id; canonical_name : string }

let request_user_equal a b = User_id.equal a.request_id b.request_id

let request_user_schema =
  Eta_schema.record1 ~name:"request_user"
    (fun request_id -> { request_id })
    (Eta_schema.required "id" User_id.schema (fun u -> u.request_id))
    ~equal:request_user_equal ()

type external_json =
  | XNull
  | XBool of bool
  | XInt of int
  | XIntlit of string
  | XFloat of float
  | XString of string
  | XArray of external_json list
  | XObject of (string * external_json) list
  | XBad of string

module Test_adapter = struct
  type nonrec external_json = external_json

  let rec of_external = function
    | XNull -> Ok Json.null
    | XBool value -> Ok (Json.bool value)
    | XInt value -> Ok (Json.int value)
    | XIntlit value -> Json.intlit value
    | XFloat value -> Json.number value
    | XString value -> Json.string value
    | XArray values -> of_external_array 0 [] values
    | XObject fields -> of_external_fields [] fields
    | XBad message -> Error [ issue ~schema_name:"test-adapter" message ]

  and of_external_array index reversed = function
    | [] -> Ok (Json.array (List.rev reversed))
    | value :: rest -> (
        match of_external value with
        | Ok value -> of_external_array (index + 1) (value :: reversed) rest
        | Error issues -> Error (at_index index issues))

  and of_external_fields reversed = function
    | [] -> Json.object_ (List.rev reversed)
    | (name, value) :: rest -> (
        match of_external value with
        | Ok value -> of_external_fields ((name, value) :: reversed) rest
        | Error issues -> Error (at_field name issues))

  let rec to_external = function
    | Json.Null -> XNull
    | Json.Bool value -> XBool value
    | Json.Number (Json.Int value) -> XInt value
    | Json.Number (Json.Intlit value) -> XIntlit value
    | Json.Number (Json.Float value) -> XFloat value
    | Json.String value -> XString value
    | Json.Array values -> XArray (List.map to_external values)
    | Json.Object fields ->
        XObject (List.map (fun (key, value) -> (key, to_external value)) fields)
end

module Test_codec = Make (Test_adapter)

let test_json_adapter_make_functor () =
  let external_json = XObject [ ("id", XString "usr_999") ] in
  let decoded =
    Test_codec.decode_result request_user_schema external_json
    |> expect_ok ~name:"adapter decode"
  in
  check_string "adapter decoded" "usr_999" (User_id.value decoded.request_id);
  let encoded =
    Test_codec.encode_result request_user_schema decoded
    |> expect_ok ~name:"adapter encode"
  in
  (match encoded with
  | XObject [ ("id", XString "usr_999") ] -> ()
  | _ -> failwith "unexpected adapter encode");
  let issues =
    Test_codec.decode_result request_user_schema (XBad "bad external json")
    |> expect_decode_error ~name:"adapter decode failure"
  in
  let issue = List.hd issues in
  check_option_string "adapter source" (Some "test-adapter") issue.schema_name;
  match issue.kind with
  | Custom message -> check_string "adapter issue" "bad external json" message
  | _ -> failwith "expected adapter custom issue"

let test_encode_failures_are_typed () =
  let one = Eta_schema.enum ~name:"one" [ ("one", 1) ] ~equal:Int.equal in
  let enum_issues = Eta_schema.encode_result one 2 |> expect_encode_error ~name:"enum" in
  check_int "enum issue count" 1 (List.length enum_issues);
  let password_only =
    let decode _ = Error [ issue "unused" ] in
    let encode = function
      | Password { min_length } ->
          Ok (Some (json_object [ ("minLength", Json.int min_length) ]))
      | _ -> Ok None
    in
    Eta_schema.tagged_union ~name:"password_only" ~tag:"_tag"
      [ Eta_schema.case ~tag:"Password" ~decode ~encode ]
      ~equal:auth_equal
  in
  let union_issues =
    Eta_schema.encode_result password_only (OAuth { issuer = "i"; client_id = "c" })
    |> expect_encode_error ~name:"tagged union"
  in
  check_int "tagged union issue count" 1 (List.length union_issues)

let test_encode_float_rejects_non_finite () =
  let cases =
    [
      ("nan", 0.0 /. 0.0);
      ("positive infinity", 1.0 /. 0.0);
      ("negative infinity", -.(1.0 /. 0.0));
    ]
  in
  List.iter
    (fun (label, value) ->
      let issues =
        Eta_schema.encode_result Eta_schema.float value
        |> expect_encode_error ~name:("float " ^ label)
      in
      check_int (label ^ " issue count") 1 (List.length issues))
    cases

let test_lazy_schema_memoizes_thunk () =
  let forced = ref 0 in
  let schema =
    Eta_schema.lazy_ (fun () ->
        incr forced;
        Eta_schema.string)
  in
  ignore (Eta_schema.decode_result schema (json_string "x") : (string, issue list) result);
  ignore (Eta_schema.encode_result schema "x" : (json, issue list) result);
  check_bool "lazy equal" (Eta_schema.equal schema "x" "x");
  check_int "lazy forced once" 1 !forced

let test_decode_int_rejects_upper_float_boundary () =
  let issues =
    Eta_schema.decode_result Eta_schema.int (json_number (float_of_int max_int))
    |> expect_decode_error ~name:"upper int float"
  in
  check_int "upper int float issue count" 1 (List.length issues);
  match List.hd issues with
  | { kind = Type_mismatch { expected = "int"; _ }; _ } -> ()
  | issue -> failwith ("unexpected issue: " ^ render_issue issue)

type non_object_union = Non_object

let non_object_union_equal a b = match (a, b) with Non_object, Non_object -> true

let test_tagged_union_rejects_non_object_case_encode () =
  let schema =
    Eta_schema.tagged_union ~name:"non_object_union" ~tag:"_tag"
      [
        Eta_schema.case ~tag:"NonObject"
          ~decode:(fun _ -> Ok Non_object)
          ~encode:(function Non_object -> Ok (Some (json_string "payload")));
      ]
      ~equal:non_object_union_equal
  in
  let issues =
    Eta_schema.encode_result schema Non_object
    |> expect_encode_error ~name:"non-object union encode"
  in
  check_int "non-object union issue count" 1 (List.length issues)

type schema_metadata = { command : string; limit : int option }

let schema_metadata_equal left right =
  String.equal left.command right.command && Option.equal Int.equal left.limit right.limit

let schema_metadata =
  let command =
    Eta_schema.string
    |> Eta_schema.with_keyword "minLength" (Json.int 1)
    |> Eta_schema.describe "Command to run"
  in
  let limit = Eta_schema.int |> Eta_schema.with_keyword "minimum" (Json.int 0) in
  Eta_schema.record2 ~name:"schema_metadata"
    (fun command limit -> { command; limit })
    (Eta_schema.required "command" command (fun value -> value.command))
    (Eta_schema.optional "limit" limit (fun value -> value.limit))
    ~equal:schema_metadata_equal ()
  |> Eta_schema.closed

let test_json_schema_derivation_and_closed_decode () =
  let expected =
    json_object
      [
        ("additionalProperties", Json.bool false);
        ("type", json_string "object");
        ( "properties",
          json_object
            [
              ( "command",
                json_object
                  [
                    ("description", json_string "Command to run");
                    ("minLength", Json.int 1);
                    ("type", json_string "string");
                  ] );
              ( "limit",
                json_object [ ("minimum", Json.int 0); ("type", json_string "integer") ]
              );
            ] );
        ("required", Json.array [ json_string "command" ]);
      ]
  in
  check_bool "derived schema"
    (Json.equal expected (Eta_schema.json_schema schema_metadata));
  match
    Eta_schema.decode_result schema_metadata
      (json_object [ ("command", json_string "pwd"); ("unknown", Json.bool true) ])
  with
  | Ok _ -> failwith "closed schema accepted unknown field"
  | Error [ issue ] ->
      check_string "unknown field path" "/unknown" (issue_to_json_pointer issue)
  | Error _ -> failwith "expected one closed-schema issue"

let test_empty_record_schema () =
  let schema =
    Eta_schema.record0 ~name:"empty" () ~equal:Unit.equal () |> Eta_schema.closed
  in
  (match Eta_schema.decode_result schema (json_object []) with
  | Ok () -> ()
  | Error issues -> failwith (render_issues issues));
  (match
     Eta_schema.decode_result schema (json_object [ ("unexpected", Json.bool true) ])
   with
  | Error [ issue ] ->
      check_string "unknown field" "/unexpected" (issue_to_json_pointer issue)
  | Error _ -> failwith "expected one unknown-field issue"
  | Ok () -> failwith "empty closed record accepted a field");
  check_bool "empty JSON schema"
    (Json.equal
       (json_object
          [
            ("additionalProperties", Json.bool false);
            ("type", json_string "object");
            ("properties", json_object []);
            ("required", Json.array []);
          ])
       (Eta_schema.json_schema schema))

type dynamic_record = { name : string; count : int option }

let test_dynamic_record_and_freeform_json () =
  let schema =
    Eta_schema.record_fields ~name:"dynamic_record" ~empty:{ name = ""; count = None }
      ~equal:(fun left right ->
        String.equal left.name right.name && Option.equal Int.equal left.count right.count)
      [
        Eta_schema.required_member "name" Eta_schema.string
          ~get:(fun value -> value.name)
          ~set:(fun value name -> { value with name });
        Eta_schema.optional_member "count" Eta_schema.int
          ~get:(fun value -> value.count)
          ~set:(fun value count -> { value with count });
      ]
    |> Eta_schema.closed
  in
  (match
     Eta_schema.decode_result schema
       (json_object [ ("name", json_string "eta"); ("count", Json.int 2) ])
   with
  | Ok { name = "eta"; count = Some 2 } -> ()
  | Ok _ -> failwith "dynamic record decoded wrong values"
  | Error issues -> failwith (render_issues issues));
  (match
     Eta_schema.decode_result schema
       (json_object [ ("name", json_string "eta"); ("extra", Json.bool true) ])
   with
  | Error _ -> ()
  | Ok _ -> failwith "closed dynamic record accepted unknown field");
  let freeform = [ ("nested", json_object [ ("answer", Json.int 42) ]) ] in
  match Eta_schema.decode_result Eta_schema.json_object (json_object freeform) with
  | Ok decoded when Json.equal (json_object decoded) (json_object freeform) -> ()
  | Ok _ -> failwith "freeform object changed values"
  | Error issues -> failwith (render_issues issues)

type scalar = Boolean of bool | Text of string

let test_untagged_union_cases () =
  let boolean =
    Eta_schema.union_case Eta_schema.bool
      ~inject:(fun value -> Boolean value)
      ~project:(function Boolean value -> Some value | Text _ -> None)
  in
  let text =
    Eta_schema.union_case Eta_schema.string
      ~inject:(fun value -> Text value)
      ~project:(function Text value -> Some value | Boolean _ -> None)
  in
  let schema =
    Eta_schema.union_cases ~name:"scalar_cases" [ boolean; text ]
      ~equal:(fun left right -> left = right)
  in
  (match Eta_schema.decode_result schema (Json.bool true) with
  | Ok (Boolean true) -> ()
  | Ok _ | Error _ -> failwith "union-case boolean decode failed");
  (match Eta_schema.decode_result schema (json_string "eta") with
  | Ok (Text "eta") -> ()
  | Ok _ | Error _ -> failwith "union-case text decode failed");
  (match Eta_schema.encode_result schema (Text "eta") with
  | Ok (Json.String "eta") -> ()
  | Ok _ | Error _ -> failwith "union-case text encode failed");
  match Eta_schema.json_schema schema with
  | Json.Object [ ("anyOf", Json.Array [ _; _ ]) ] -> ()
  | _ -> failwith "union-case schema must derive anyOf"

let test_untagged_union_and_custom () =
  let boolean =
    Eta_schema.custom
      ~equal:(fun left right -> left = right)
      ~decode:(function
        | Json.Bool value -> Ok (Boolean value) | _ -> Error [ issue "not boolean" ])
      ~encode:(function
        | Boolean value -> Ok (Json.bool value) | Text _ -> Error [ issue "not boolean" ])
      ~json_schema:(json_object [ ("type", json_string "boolean") ])
      ()
  in
  let text =
    Eta_schema.custom
      ~equal:(fun left right -> left = right)
      ~decode:(function
        | Json.String value -> Ok (Text value)
        | value ->
            Error
              [
                type_mismatch ~expected:"string"
                  ~got:
                    (match value with
                    | Json.Null -> "null"
                    | Json.Bool _ -> "boolean"
                    | Json.Number _ -> "number"
                    | Json.String _ -> "string"
                    | Json.Array _ -> "array"
                    | Json.Object _ -> "object")
                  ();
              ])
      ~encode:(function
        | Text value -> Ok (json_string value) | Boolean _ -> Error [ issue "not text" ])
      ~json_schema:(json_object [ ("type", json_string "string") ])
      ()
  in
  let schema =
    Eta_schema.union ~name:"scalar" [ boolean; text ] ~equal:(fun left right ->
        left = right)
  in
  (match Eta_schema.decode_result schema (Json.bool true) with
  | Ok (Boolean true) -> ()
  | Ok _ | Error _ -> failwith "union boolean decode failed");
  (match Eta_schema.decode_result schema (json_string "eta") with
  | Ok (Text "eta") -> ()
  | Ok _ | Error _ -> failwith "union text decode failed");
  (match Eta_schema.encode_result schema (Text "eta") with
  | Ok (Json.String "eta") -> ()
  | Ok _ | Error _ -> failwith "union text encode failed");
  match Eta_schema.json_schema schema with
  | Json.Object [ ("anyOf", Json.Array [ _; _ ]) ] -> ()
  | _ -> failwith "union schema must derive anyOf"

let rejected name = function
  | Ok _ -> failwith (name ^ ": expected construction to be rejected")
  | Error issues -> issues

(* ^jsonvalid-4egk: public construction rejects non-finite floats, malformed
   JSON number literals, and malformed UTF-8 string values and object names. *)
let test_json_construction_rejects_invalid_values () =
  List.iter
    (fun (label, value) ->
      let issues = rejected ("non-finite " ^ label) (Json.number value) in
      check_int (label ^ " issue count") 1 (List.length issues))
    [
      ("nan", Float.nan);
      ("infinity", Float.infinity);
      ("negative infinity", Float.neg_infinity);
    ];
  List.iter
    (fun literal ->
      let issues = rejected ("literal " ^ literal) (Json.intlit literal) in
      check_int ("literal issue count " ^ literal) 1 (List.length issues))
    [
      "";
      "-";
      "--1";
      "01";
      "-01";
      "+1";
      "1.";
      ".5";
      "1e";
      "1e+";
      "1e-";
      "0x10";
      " 1";
      "1 ";
      "1.2.3";
      "1,5";
    ];
  List.iter
    (fun (label, value) ->
      let issues = rejected ("utf8 " ^ label) (Json.string value) in
      check_int (label ^ " issue count") 1 (List.length issues))
    [
      ("lone continuation", "\xff");
      ("truncated two-byte", "\xc3");
      ("truncated three-byte", "\xe2\x82");
      ("truncated four-byte", "\xf0\x9f\x98");
      ("overlong two-byte", "\xc0\xaf");
      ("overlong three-byte", "\xe0\x80\xaf");
      ("surrogate", "\xed\xa0\x80");
      ("above unicode maximum", "\xf5\x80\x80\x80");
      ("invalid start byte", "\xf8\x88\x80\x80\x80");
      ("embedded invalid byte", "ok\xffok");
    ];
  match
    rejected "utf8 object name"
      (Json.object_ [ ("ok", Json.int 1); ("bad\xff", Json.int 2) ])
  with
  | [ { path = [ Field "bad\xff" ]; kind = Custom _; _ } ] -> ()
  | issues ->
      failwith ("unexpected object name issues: " ^ Eta_schema.render_issues issues)

(* ^jsonvalid-4egk: values whose inputs already guarantee validity stay
   constructible, and valid large literals remain exact. *)
let test_json_construction_accepts_valid_values () =
  List.iter
    (fun value -> ignore (Json.number value : (json, issue list) result))
    [ 0.0; -0.0; 1.5; -1.5; 1e100; -1e-100; float_of_int max_int ];
  List.iter
    (fun literal -> ignore (Json.intlit literal : (json, issue list) result))
    [
      "0";
      "-0";
      "10";
      "0.5";
      "-1.5e-10";
      "1E+2";
      "1e999";
      "9007199254740993";
      "18446744073709551616";
    ];
  check_string "large literal stays exact" "9007199254740993"
    (Json.to_string (json_intlit "9007199254740993"));
  check_string "exponent literal stays exact" "1e999"
    (Json.to_string (json_intlit "1e999"));
  List.iter
    (fun value -> ignore (Json.string value : (json, issue list) result))
    [
      "";
      "ascii";
      "\xc3\xa9";
      "\xe4\xb8\xad";
      "\xf0\x9f\x98\x80";
      "\xed\x9f\xbf";
      "\xee\x80\x80";
      "\xf4\x8f\xbf\xbf";
      "\000\n\t\r\b\012";
    ];
  ignore (Json.object_ [ ("ok", Json.int 1) ] : (json, issue list) result);
  ignore (Json.array [ Json.int 1; json_string "x" ] : json);
  check_bool "duplicate names preserved"
    (Json.equal
       (json_object [ ("a", Json.int 1); ("a", Json.int 2) ])
       (json_object [ ("a", Json.int 1); ("a", Json.int 2) ]))

(* ^jsonvalid-4egk: valid constructed trees serialize and parse back without
   malformed output, including nested arrays and objects. *)
let test_json_construction_serialization_roundtrip () =
  let tree =
    json_object
      [
        ( "nested",
          Json.array
            [
              json_object [ ("answer", Json.int 42); ("text", json_string "\xc3\xa9\n") ];
              Json.null;
              Json.bool true;
            ] );
        ("number", json_number 1.5);
        ("literal", json_intlit "18446744073709551616");
      ]
  in
  let rendered = Json.to_string tree in
  check_string "exact compact rendering"
    "{\"nested\": [{\"answer\": 42, \"text\": \"\xc3\xa9\\n\"}, null, true], \"number\": \
     1.5, \"literal\": 18446744073709551616}"
    rendered;
  check_string "escaped control characters round trip" "\000\n"
    (unescape_json_string (Json.to_string (json_string "\000\n")))

(* ^jsonvalid-ug7c: adapters report invalid external data as structured issues
   as structured issues at the pure boundary. *)
let test_json_adapter_reports_invalid_external_data () =
  let cases =
    [
      ("non-finite number", XFloat Float.nan);
      ("malformed literal", XIntlit "01");
      ("invalid utf8 value", XString "\xff");
      ("invalid utf8 name", XObject [ ("ok", XInt 1); ("bad\xff", XInt 2) ]);
      ("unsupported extension", XBad "unsupported non-standard JSON value");
    ]
  in
  List.iter
    (fun (label, external_json) ->
      match Test_codec.decode_result request_user_schema external_json with
      | Ok _ -> failwith (label ^ ": expected adapter rejection")
      | Error issues -> check_bool (label ^ " reports issues") (issues <> []))
    cases;
  let issues =
    Test_codec.decode_result request_user_schema (XString "\xff")
    |> expect_decode_error ~name:"adapter invalid utf8"
  in
  check_bool "adapter rejection is typed" (issues <> []);
  let encode_issues =
    Test_codec.encode_result Eta_schema.string "\xff"
    |> expect_encode_error ~name:"adapter invalid utf8 encode"
  in
  check_bool "adapter encode rejection is typed" (encode_issues <> [])

(* ^njson-3ph9: the pure entry points are immediate. v1's deferred-conversion
   suite went with the runtime; what remains is that one call runs the codec
   once, and a custom codec's callbacks are counted here. *)

let instrumented_schema calls =
  Eta_schema.custom ~equal:Int.equal
    ~decode:(fun _ ->
      incr calls;
      Ok 1)
    ~encode:(fun _ ->
      incr calls;
      Ok Json.null)
    ~json_schema:Json.null ()

let test_result_apis_stay_immediate () =
  let calls = ref 0 in
  let schema = instrumented_schema calls in
  ignore (Eta_schema.decode_result schema Json.null : (int, issue list) result);
  check_int "decode_result is immediate" 1 !calls;
  ignore (Eta_schema.encode_result schema 1 : (json, issue list) result);
  check_int "encode_result is immediate" 2 !calls;
  let adapter_calls = ref 0 in
  let module A = Make (struct
    type external_json = json

    let of_external json =
      incr adapter_calls;
      Ok json

    let to_external json =
      incr adapter_calls;
      json
  end) in
  ignore (A.decode_result schema Json.null : (int, issue list) result);
  check_int "adapter decode_result codec is immediate" 3 !calls;
  check_int "adapter decode_result of_external is immediate" 1 !adapter_calls;
  ignore (A.encode_result schema 1 : (json, issue list) result);
  check_int "adapter encode_result codec is immediate" 4 !calls;
  check_int "adapter encode_result to_external is immediate" 2 !adapter_calls;
  ignore (Eta_schema.json_schema schema : json);
  check_int "json_schema derivation invokes no codec" 4 !calls;
  check_bool "schema equality invokes no codec" (Eta_schema.equal schema 1 1);
  check_int "schema equality invokes no codec" 4 !calls

let test_adapter_issue_paths () =
  let pointer external_json =
    match Test_codec.decode_result request_user_schema external_json with
    | Ok _ -> failwith "expected adapter rejection"
    | Error [ issue ] -> issue_to_json_pointer issue
    | Error issues -> failwith ("expected one adapter issue: " ^ render_issues issues)
  in
  check_string "root adapter pointer" "" (pointer (XBad "bad external json"));
  check_string "nested index pointer" "/0/1"
    (pointer (XArray [ XArray [ XInt 0; XFloat Float.nan ] ]));
  check_string "field and index pointer" "/a~1b/1"
    (pointer (XObject [ ("a/b", XArray [ XInt 0; XString "\xff" ]) ]));
  check_string "three level pointer" "/0/a/1"
    (pointer (XArray [ XObject [ ("a", XArray [ XInt 0; XString "\xff" ]) ] ]));
  check_string "tilde name pointer" "/a~0b" (pointer (XObject [ ("a~b", XIntlit "01") ]));
  check_string "nonzero index pointer" "/2"
    (pointer (XArray [ XInt 0; XInt 1; XIntlit "1." ]))

(* ---- eta-next additions: marks, pointers, printers, dependencies ---------- *)

let check_bool name value = if not value then Alcotest.fail name

(* ^nschema-ubrs: a nested record with a secret field that comes from an
   environment variable, an array of such records, and an optional field whose
   environment variable may override it. *)
type mark_credentials = { api_key : string; endpoint : string }
type mark_models = { credentials : mark_credentials; retries : int }

type mark_service = {
  name : string;
  models : mark_models;
  keys : mark_credentials list;
  debug : bool option;
}

type marked_member = { token : string }

let mark_credentials_schema =
  record2 ~name:"credentials"
    (fun api_key endpoint -> { api_key; endpoint })
    (required ~secret:true ~env:"OPENROUTER_API_KEY" "api_key" string (fun r -> r.api_key))
    (required "endpoint" string (fun r -> r.endpoint))
    ~equal:( = ) ()

let mark_models_schema =
  record2 ~name:"models"
    (fun credentials retries -> { credentials; retries })
    (required "credentials" mark_credentials_schema (fun r -> r.credentials))
    (required "retries" int (fun r -> r.retries))
    ~equal:( = ) ()

let mark_service_schema =
  record4 ~name:"service"
    (fun name models keys debug -> { name; models; keys; debug })
    (required "name" string (fun r -> r.name))
    (required "models" mark_models_schema (fun r -> r.models))
    (required "keys" (array mark_credentials_schema) (fun r -> r.keys))
    (optional ~env:"SERVICE_DEBUG" "debug" bool (fun r -> r.debug))
    ~equal:( = ) ()

let mark_line mark =
  Printf.sprintf "%s|%s|%b|%s" mark.pointer mark.name mark.secret
    (match mark.env with None -> "-" | Some env -> env)

let test_field_marks_metadata () =
  let expected =
    [
      "/name|name|false|-";
      "/models|models|false|-";
      "/models/credentials|credentials|false|-";
      "/models/credentials/api_key|api_key|true|OPENROUTER_API_KEY";
      "/models/credentials/endpoint|endpoint|false|-";
      "/models/retries|retries|false|-";
      "/keys|keys|false|-";
      "/keys/api_key|api_key|true|OPENROUTER_API_KEY";
      "/keys/endpoint|endpoint|false|-";
      "/debug|debug|false|SERVICE_DEBUG";
    ]
  in
  Alcotest.(check (list string))
    "declaration order, pointer paths, secret and env marks" expected
    (List.map mark_line (field_marks mark_service_schema));
  (* The dynamic-arity members carry the same marks. *)
  let member_schema =
    record_fields ~name:"marked_member" ~empty:{ token = "" } ~equal:( = )
      [
        required_member ~secret:true ~env:"MEMBER_TOKEN" "token" string
          ~get:(fun r -> r.token)
          ~set:(fun _ value -> { token = value });
      ]
  in
  Alcotest.(check (list string))
    "member marks"
    [ "/token|token|true|MEMBER_TOKEN" ]
    (List.map mark_line (field_marks member_schema));
  (* Primitives, enums, unions and custom schemas declare no fields. *)
  Alcotest.(check (list string)) "primitive" [] (List.map mark_line (field_marks string));
  Alcotest.(check (list string))
    "enum" []
    (List.map mark_line
       (field_marks (enum ~name:"flag" [ ("on", true) ] ~equal:Bool.equal)));
  Alcotest.(check (list string))
    "custom" []
    (List.map mark_line
       (field_marks
          (custom ~equal:Int.equal
             ~decode:(fun _ -> Ok 1)
             ~encode:(fun _ -> Ok Json.null)
             ~json_schema:Json.null ())))

let mark_service_value =
  {
    name = "leash";
    models =
      {
        credentials = { api_key = "sk-secret"; endpoint = "https://api.example" };
        retries = 3;
      };
    keys =
      [
        { api_key = "key-one"; endpoint = "https://one.example" };
        { api_key = "key-two"; endpoint = "https://two.example" };
      ];
    debug = Some true;
  }

let test_encode_redacted () =
  let plain = encode_ok ~name:"plain" mark_service_schema mark_service_value in
  let redacted =
    expect_ok ~name:"redacted" (encode_redacted mark_service_schema mark_service_value)
  in
  let member name json =
    match Json.find name json with
    | Some value -> value
    | None -> Alcotest.failf "missing member %s" name
  in
  let models text = member "models" text in
  Alcotest.(check string)
    "plain encoding keeps the secret" "\"sk-secret\""
    (Json.to_string (member "api_key" (member "credentials" (models plain))));
  Alcotest.(check string)
    "nested secret redacted" "\"<redacted>\""
    (Json.to_string (member "api_key" (member "credentials" (models redacted))));
  Alcotest.(check string)
    "nested non-secret kept" "\"https://api.example\""
    (Json.to_string (member "endpoint" (member "credentials" (models redacted))));
  Alcotest.(check string)
    "unmarked field untouched" "\"leash\""
    (Json.to_string (member "name" redacted));
  Alcotest.(check string)
    "non-secret environment field untouched" "true"
    (Json.to_string (member "debug" redacted));
  (match member "keys" redacted with
  | Json.Array [ first; second ] ->
      Alcotest.(check string)
        "array element secret redacted" "\"<redacted>\""
        (Json.to_string (member "api_key" first));
      Alcotest.(check string)
        "second array element secret redacted" "\"<redacted>\""
        (Json.to_string (member "api_key" second));
      Alcotest.(check string)
        "array element non-secret kept" "\"https://two.example\""
        (Json.to_string (member "endpoint" second))
  | _ -> Alcotest.fail "keys must stay an array of two elements");
  (* An absent optional field is not invented by redaction. *)
  let without_debug = { mark_service_value with debug = None } in
  let redacted =
    expect_ok ~name:"redacted optional"
      (encode_redacted mark_service_schema without_debug)
  in
  Alcotest.(check (option json_testable))
    "absent optional stays absent" None (Json.find "debug" redacted)

(* ^njson-fib9: paths render as RFC 6901 pointers and escape ~ and /. *)
let test_json_pointer_escaping () =
  Alcotest.(check string) "root" "" (json_pointer []);
  Alcotest.(check string) "field" "/name" (json_pointer [ Field "name" ]);
  Alcotest.(check string) "index" "/2" (json_pointer [ Index 2 ]);
  Alcotest.(check string)
    "tilde and slash" "/a~0b~1c/0"
    (json_pointer [ Field "a~b/c"; Index 0 ]);
  Alcotest.(check string)
    "issue pointer" "/a~1b/1"
    (issue_to_json_pointer
       { path = [ Field "a/b"; Index 1 ]; schema_name = None; kind = Custom "x" })

(* ^njson-fib9: every failing branch of one document is reported, each with the
   pointer of the value that produced it. *)
let test_every_issue_is_reported () =
  let json =
    json_object
      [
        ("name", Json.int 7);
        ( "models",
          json_object
            [
              ("credentials", json_object [ ("endpoint", Json.int 1) ]);
              ("retries", json_string "soon");
            ] );
        ( "keys",
          Json.array
            [
              json_object [ ("api_key", json_string "k"); ("endpoint", json_string "e") ];
              json_object [ ("api_key", json_string "k2") ];
            ] );
      ]
  in
  let issues =
    expect_decode_error ~name:"every issue" (decode_result mark_service_schema json)
  in
  Alcotest.(check (list string))
    "all pointers, outermost to innermost"
    [
      "/name";
      "/models/credentials/api_key";
      "/models/credentials/endpoint";
      "/models/retries";
      "/keys/1/endpoint";
    ]
    (List.map issue_to_json_pointer issues);
  match issues with
  | first :: second :: _ ->
      Alcotest.(check bool)
        "field type mismatch" true
        (match first.kind with
        | Type_mismatch { expected = "string"; got = "7" } -> true
        | _ -> false);
      Alcotest.(check bool)
        "missing nested field keeps its schema name" true
        (match second with
        | {
         path = [ Field "models"; Field "credentials"; Field "api_key" ];
         schema_name = Some "credentials";
         kind = Missing_field "api_key";
         _;
        } ->
            true
        | _ -> false)
  | _ -> Alcotest.fail "expected at least two issues"

(* ^nschema-fwsu: issues are a plain variant with a printer; a caller maps them
   by matching, never by string comparison. *)
let test_issue_kind_and_printers () =
  let issues = expect_decode_error ~name:"string" (decode_result string (Json.int 1)) in
  (match issues with
  | [
   {
     kind = Type_mismatch { expected = "string"; got = "1" };
     path = [];
     schema_name = None;
   };
  ] ->
      ()
  | _ -> Alcotest.failf "unexpected type mismatch: %s" (render_issues issues));
  let issues =
    expect_decode_error ~name:"missing"
      (decode_result
         (record1 ~name:"user"
            (fun name -> name)
            (required "name" string (fun n -> n))
            ~equal:String.equal ())
         (json_object []))
  in
  (match issues with
  | [
   { kind = Missing_field "name"; path = [ Field "name" ]; schema_name = Some "user" };
  ] ->
      ()
  | _ -> Alcotest.failf "unexpected missing field: %s" (render_issues issues));
  let bounded =
    refine ~name:"bounded"
      (fun value -> if String.length value <= 2 then [] else [ issue "too long" ])
      string
  in
  let issues =
    expect_decode_error ~name:"refine" (decode_result bounded (json_string "abc"))
  in
  (match issues with
  | [ { kind = Refinement_failed { name = "bounded"; reason = "too long" }; _ } ] -> ()
  | _ -> Alcotest.failf "unexpected refinement issue: %s" (render_issues issues));
  let custom_issue = issue ~path:[ Field "field" ] "custom reason" in
  (match custom_issue.kind with
  | Custom "custom reason" -> ()
  | _ -> Alcotest.fail "custom issue kind");
  Alcotest.(check string)
    "issue printer" "custom reason at field"
    (Format.asprintf "%a" pp_issue custom_issue);
  Alcotest.(check string)
    "issues printer" "custom reason; custom reason at field"
    (Format.asprintf "%a" pp_issues [ issue "custom reason"; custom_issue ]);
  Alcotest.(check string)
    "error printer for decode" "decode: custom reason"
    (Format.asprintf "%a" pp_error (`Decode [ issue "custom reason" ]));
  Alcotest.(check string)
    "error printer for encode" "encode: custom reason"
    (Format.asprintf "%a" pp_error (`Encode [ issue "custom reason" ]))

(* ^njson-3vf4: bounds and ranges are expressed by refine over string and int. *)
let test_refine_bounds_and_ranges () =
  let bounded_string =
    refine ~name:"bounded_string"
      (fun value ->
        if String.length value >= 3 && String.length value <= 8 then []
        else [ issue "length must be between 3 and 8" ])
      string
  in
  let ranged_int =
    refine ~name:"ranged_int"
      (fun value -> if value >= 1 && value <= 10 then [] else [ issue "out of range" ])
      int
  in
  let pair =
    record2 ~name:"pair"
      (fun label count -> (label, count))
      (required "label" bounded_string (fun (label, _) -> label))
      (required "count" ranged_int (fun (_, count) -> count))
      ~equal:( = ) ()
  in
  Alcotest.(check (pair string int))
    "inside the bounds" ("eta", 7)
    (decode_ok ~name:"inside" pair
       (json_object [ ("label", json_string "eta"); ("count", Json.int 7) ]));
  let issues =
    expect_decode_error ~name:"outside"
      (decode_result pair
         (json_object [ ("label", json_string "et"); ("count", Json.int 11) ]))
  in
  Alcotest.(check (list string))
    "both bounds reported" [ "/label"; "/count" ]
    (List.map issue_to_json_pointer issues);
  Alcotest.(check bool)
    "bound names travel with the issue" true
    (List.for_all
       (fun issue ->
         match issue.kind with
         | Refinement_failed { name; _ } ->
             String.equal name "bounded_string" || String.equal name "ranged_int"
         | _ -> false)
       issues);
  (* A missing field is still a missing field, not a refinement failure. *)
  let issues =
    expect_decode_error ~name:"missing" (decode_result pair (json_object []))
  in
  Alcotest.(check bool)
    "missing fields" true
    (List.for_all
       (fun issue -> match issue.kind with Missing_field _ -> true | _ -> false)
       issues);
  let issues =
    expect_decode_error ~name:"wrong type" (decode_result bounded_string (Json.int 3))
  in
  match issues with
  | [
   {
     kind = Type_mismatch { expected = "string"; got = "3" };
     schema_name = Some "bounded_string";
   };
  ] ->
      ()
  | _ -> Alcotest.failf "unexpected issue: %s" (render_issues issues)

(* ^nschema-jcbp: eta_schema depends on the standard library alone; the two
   neighbours keep to their declared ceilings.

   These checks read the source tree, not the copy dune keeps under [_build]:
   a missing directory under [_build] would be vacuous. Dune runs a test with
   its working directory set to the test's directory inside the build context,
   so walk up to the workspace root, which is the directory holding both
   [dune-project] and either [.git] or [flake.nix]. *)
let is_source_root dir =
  Sys.file_exists (Filename.concat dir "dune-project")
  && (Sys.file_exists (Filename.concat dir ".git")
     || Sys.file_exists (Filename.concat dir "flake.nix"))

let rec find_source_root dir =
  if is_source_root dir then dir
  else
    let parent = Filename.dirname dir in
    if String.equal parent dir then
      Alcotest.failf "source tree not found above %s" (Sys.getcwd ())
    else find_source_root parent

let root () = find_source_root (Sys.getcwd ())
let path relative = Filename.concat (root ()) relative

let read_file relative =
  let channel = open_in_bin (path relative) in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let contains text needle =
  let needle_length = String.length needle in
  let rec loop index =
    if index + needle_length > String.length text then false
    else if String.equal (String.sub text index needle_length) needle then true
    else loop (index + 1)
  in
  needle_length > 0 && loop 0

let libraries relative =
  let text = read_file relative in
  let marker = "(libraries" in
  let rec find index =
    if index + String.length marker > String.length text then None
    else if String.equal (String.sub text index (String.length marker)) marker then
      Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> []
  | Some start ->
      let stop = String.index_from text start ')' in
      String.sub text (start + String.length marker) (stop - start - String.length marker)
      |> String.split_on_char ' '
      |> List.filter (fun word -> not (String.equal word ""))

let schema_sources () =
  Sys.readdir (path "lib/schema")
  |> Array.to_list
  |> List.filter (fun name ->
      Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli")
  |> List.map (fun name -> Filename.concat "lib/schema" name)

let test_package_dependencies () =
  Alcotest.(check (list string))
    "eta_schema declares no library" [] (libraries "lib/schema/dune");
  Alcotest.(check (list string))
    "eta_json depends on yojson only" [ "yojson" ] (libraries "lib/json/dune");
  Alcotest.(check (list string))
    "eta_schema_yojson depends on eta_schema and yojson" [ "eta_schema"; "yojson" ]
    (libraries "lib/schema_yojson/dune");
  List.iter
    (fun relative ->
      let text = read_file relative in
      List.iter
        (fun forbidden ->
          Alcotest.(check bool)
            (Printf.sprintf "%s does not mention %s" relative forbidden)
            false (contains text forbidden))
        [ "Eta."; "Effect"; "Runtime" ])
    (schema_sources ())

(* ^nschema-liiu: only code and tests moved; v1's docs stubs, audit/ and bench/
   directories stayed behind. *)
let test_v1_extras_left_behind () =
  List.iter
    (fun relative ->
      Alcotest.(check bool)
        (relative ^ " is absent") false
        (Sys.file_exists (path relative)))
    [
      "lib/schema/docs";
      "lib/schema/bench";
      "lib/schema/audit";
      "lib/json/docs";
      "lib/json/bench";
      "lib/schema_yojson/docs";
      "lib/schema_yojson/bench";
    ]

let () =
  Alcotest.run "eta_schema"
    [
      ( "schema",
        [
          Alcotest.test_case "njson-3vf4 njson-3ph9 config roundtrip" `Quick
            test_config_roundtrip;
          Alcotest.test_case "njson-fib9 many issues" `Quick test_many_issues;
          Alcotest.test_case "njson-3vf4 tagged and recursive" `Quick
            test_tagged_and_recursive;
          Alcotest.test_case "njson-fib9 issue paths distinguish fields and indexes"
            `Quick test_issue_paths_distinguish_fields_and_indexes;
          Alcotest.test_case "njson-fib9 issue source discriminator" `Quick
            test_issue_source_discriminator;
          Alcotest.test_case "njson-3ph9 json number rendering" `Quick
            test_json_number_rendering;
          Alcotest.test_case "njson-3ph9 json string rendering" `Quick
            test_json_string_rendering;
          Alcotest.test_case "njson-3ph9 json adapter make functor" `Quick
            test_json_adapter_make_functor;
          Alcotest.test_case "nschema-59sn encode failures are typed" `Quick
            test_encode_failures_are_typed;
          Alcotest.test_case "nschema-59sn encode float rejects non-finite" `Quick
            test_encode_float_rejects_non_finite;
          Alcotest.test_case "nschema-59sn tagged union rejects non-object case encode"
            `Quick test_tagged_union_rejects_non_object_case_encode;
          Alcotest.test_case "njson-3vf4 lazy schema memoizes thunk" `Quick
            test_lazy_schema_memoizes_thunk;
          Alcotest.test_case "njson-3vf4 decode int rejects upper float boundary" `Quick
            test_decode_int_rejects_upper_float_boundary;
          Alcotest.test_case "njson-3vf4 json schema derivation and closed decode" `Quick
            test_json_schema_derivation_and_closed_decode;
          Alcotest.test_case "njson-3vf4 empty record schema" `Quick
            test_empty_record_schema;
          Alcotest.test_case "njson-3vf4 dynamic record and freeform JSON" `Quick
            test_dynamic_record_and_freeform_json;
          Alcotest.test_case "njson-3vf4 untagged union cases" `Quick
            test_untagged_union_cases;
          Alcotest.test_case "njson-3vf4 untagged union and custom schema" `Quick
            test_untagged_union_and_custom;
          Alcotest.test_case "njson-3ph9 json construction rejects invalid values" `Quick
            test_json_construction_rejects_invalid_values;
          Alcotest.test_case "njson-3ph9 json construction accepts valid values" `Quick
            test_json_construction_accepts_valid_values;
          Alcotest.test_case "njson-3ph9 json construction serialization roundtrip" `Quick
            test_json_construction_serialization_roundtrip;
          Alcotest.test_case "njson-3ph9 json adapter reports invalid external data"
            `Quick test_json_adapter_reports_invalid_external_data;
          Alcotest.test_case "njson-3ph9 result APIs stay immediate" `Quick
            test_result_apis_stay_immediate;
          Alcotest.test_case "njson-fib9 adapter issue paths" `Quick
            test_adapter_issue_paths;
          Alcotest.test_case "njson-3vf4 refine expresses string bounds and int ranges"
            `Quick test_refine_bounds_and_ranges;
          Alcotest.test_case "njson-fib9 every failing branch reported with its pointer"
            `Quick test_every_issue_is_reported;
          Alcotest.test_case "njson-fib9 json pointer escaping" `Quick
            test_json_pointer_escaping;
          Alcotest.test_case "nschema-fwsu issue kinds are a plain variant with printers"
            `Quick test_issue_kind_and_printers;
          Alcotest.test_case "nschema-ubrs field marks metadata" `Quick
            test_field_marks_metadata;
          Alcotest.test_case "nschema-ubrs encode with secrets redacted" `Quick
            test_encode_redacted;
          Alcotest.test_case
            "nschema-jcbp eta_schema depends on the standard library only" `Quick
            test_package_dependencies;
          Alcotest.test_case "nschema-liiu v1 docs, audit and bench stayed behind" `Quick
            test_v1_extras_left_behind;
        ] );
    ]
