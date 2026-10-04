(* ^nderive-s2lt ^nderive-u3ux ^nderive-9atb ^nderive-07js ^nderive-i3v2
   ^nderive-sfta ^nderive-cd80 ^nderive-p4tq ^nderive-ufnu ^nderive-e5va *)
let golden label expected json =
  Alcotest.(check string) label expected (Yojson.Safe.to_string json)

let expect_ok = function
  | Ok value -> value
  | Error error -> Alcotest.failf "unexpected decoder error: %s" error

let contains needle text =
  let n = String.length needle in
  let rec loop i =
    i + n <= String.length text && (String.sub text i n = needle || loop (i + 1))
  in
  loop 0

let test_encoders () =
  let open Native_encoders in
  golden "abstract encoder signature" "3" (yojson_of_t (make 3));
  golden "opaque constituent alias" "4" (yojson_of_alias (Manual_encoder.make 4));
  golden "nullary string" {|"Idle"|} (yojson_of_variant Idle);
  golden "single payload" {|["One",2]|} (yojson_of_variant (One 2));
  golden "multiple payloads" {|["Many","x",true]|} (yojson_of_variant (Many ("x", true)));
  golden "named nullary" {|"plain"|} (yojson_of_renamed Plain);
  golden "named payload" {|["payload",8]|} (yojson_of_renamed (Payload 8));
  golden "record/container/option defaults"
    {|{"secretKey":4,"retained":null,"raw":{"x":[null,9]},"names":["a","b"],"pair":[1.5,true],"grid":[1,2],"initial":"z","empty":null,"defaulted":7}|}
    (yojson_of_record
       {
         secret = Manual_encoder.make 4;
         omitted = None;
         retained = None;
         raw = `Assoc [ ("x", `List [ `Null; `Int 9 ]) ];
         names = [ "a"; "b" ];
         pair = (1.5, true);
         grid = [| 1; 2 |];
         initial = 'z';
         empty = ();
         defaulted = 7;
       });
  golden "empty-record marker" "{}" (yojson_of_empty_object ());
  golden "recursive encoder" {|["Node",[["Leaf",1],["Node",[]]]]|}
    (yojson_of_tree (Node [ Leaf 1; Node [] ]));
  golden "mutual recursive encoder" {|["A",{"next":[["A",null]]}]|}
    (yojson_of_a (A (Some { next = [ A None ] })));
  golden "module-local encoder-only reference" {|{"leaf":6}|}
    (Local.yojson_of_t { leaf = Manual_encoder.make 6 });
  golden "nonrec local encoder-only re-export" {|{"leaf":6}|}
    (Local.Reexport.yojson_of_t { leaf = Manual_encoder.make 6 });
  golden "sibling encoder-only" {|{"secret":5}|}
    (Module_codecs.Only.yojson_of_t { secret = Manual_encoder.make 5; nick = None })

let test_modules () =
  let open Module_codecs in
  let item : First.item = { city = "Oslo" } in
  let left : First.t = { item; nick = None; count = 7 } in
  let right = Second.Pair ("v", 2) in
  golden "sibling record" {|{"item":{"city":"Oslo"},"count":7}|} (First.yojson_of_t left);
  golden "nonrec local bidirectional re-export" {|{"item":{"city":"Oslo"},"count":7}|}
    (First.Reexport.yojson_of_t left);
  Alcotest.(check bool)
    "nonrec local decoder re-export" true
    (expect_ok (First.Reexport.t_of_yojson (First.Reexport.yojson_of_t left)) = left);
  golden "sibling variant" {|["Pair","v",2]|} (Second.yojson_of_t right);
  golden "sibling nullary" {|"Idle"|} (Second.yojson_of_t Second.Idle);
  let value : Qualified.t = { left; right; deep = [ item ] } in
  let json = Qualified.yojson_of_t value in
  golden "qualified and multi-level references"
    {|{"left":{"item":{"city":"Oslo"},"count":7},"right":["Pair","v",2],"deep":[{"city":"Oslo"}]}|}
    json;
  Alcotest.(check bool)
    "qualified round-trip" true
    (expect_ok (Qualified.t_of_yojson json) = value);
  Alcotest.(check bool)
    "local reference/default/None decoder" true
    (expect_ok
       (First.t_of_yojson (`Assoc [ ("item", `Assoc [ ("city", `String "Oslo") ]) ]))
    = left);
  Alcotest.(check (result unit string))
    "unknown fields remain errors" (Error "t: unknown field extra")
    (Result.map
       (fun _ -> ())
       (First.t_of_yojson
          (`Assoc [ ("item", `Assoc [ ("city", `String "Oslo") ]); ("extra", `Null) ])));
  (match First.t_of_yojson (`Assoc [ ("item", `Assoc [ ("city", `Int 4) ]) ]) with
  | Error message ->
      Alcotest.(check bool) "nested path" true (contains "t.item: item.city:" message)
  | Ok _ -> Alcotest.fail "invalid nested record decoded");
  let tree = First.Deep.Node (First.Deep.Leaf 1, First.Deep.Leaf 2) in
  Alcotest.(check bool)
    "nested recursive round-trip" true
    (expect_ok (First.Deep.tree_of_yojson (First.Deep.yojson_of_tree tree)) = tree);
  let mutual : First.Deep.a = { b = { value = 8 } } in
  Alcotest.(check bool)
    "nested mutual round-trip" true
    (expect_ok (First.Deep.a_of_yojson (First.Deep.yojson_of_a mutual)) = mutual);
  Alcotest.(check int)
    "inline signature in implementation" 9
    (expect_ok (Constrained.t_of_yojson (Constrained.yojson_of_t 9)))

let test_no_decoder_generation () =
  List.iter
    (fun (filename, source) ->
      match Ppx_yojson_minimal.Derive.process ~filename ~source with
      | Error message -> Alcotest.fail message
      | Ok text ->
          List.iter
            (fun name ->
              Alcotest.(check bool)
                (filename ^ ": absent " ^ name)
                false (contains name text))
            [ "_of_yojson"; "ppx_yojson_decode"; "_ppx_yojson_error" ])
    [
      ("only.ml", "type t = int [@@deriving yojson_of]");
      ("only.mli", "type t [@@deriving yojson_of]");
      ("nested.ml", "module M = struct type t = int [@@deriving yojson_of] end");
      ("nested.mli", "module M : sig type t [@@deriving yojson_of] end");
    ]

let test_unsupported () =
  let cases =
    [
      ( "functor body",
        "functors",
        "bad.ml",
        "module F (X : sig end) = struct type t = int [@@deriving %s] end" );
      ( "functor argument",
        "functors",
        "bad.ml",
        "module F (X : sig type t = int [@@deriving %s] end) = struct end" );
      ( "functor signature",
        "functors",
        "bad.mli",
        "module F : functor (X : sig end) -> sig type t = int [@@deriving %s] end" );
      ( "functor module type",
        "functors",
        "bad.mli",
        "module type F = functor (X : sig type t [@@deriving %s] end) -> sig end" );
      ( "packed module",
        "first-class modules",
        "bad.ml",
        "module type S = sig type t end let value = (module struct type t = int \
         [@@deriving %s] end : S)" );
      ( "unpacked module",
        "first-class modules",
        "bad.ml",
        "module type S = sig type t end module M = (val (module struct type t = int \
         [@@deriving %s] end : S))" );
      ( "local module",
        "local modules",
        "bad.ml",
        "let f () = let module M = struct type t = int [@@deriving %s] end in ()" );
      ( "private implementation",
        "private types",
        "bad.ml",
        "module M = struct type t = private int [@@deriving %s] end" );
      ( "private signature",
        "private types",
        "bad.mli",
        "module M : sig type t = private int [@@deriving %s] end" );
      ( "GADT implementation",
        "GADT",
        "bad.ml",
        "module M = struct type t = C : t [@@deriving %s] end" );
      ( "GADT signature",
        "GADT",
        "bad.mli",
        "module M : sig type t = C : t [@@deriving %s] end" );
      ( "inline implementation",
        "inline record",
        "bad.ml",
        "module M = struct type t = C of { x : int } [@@deriving %s] end" );
      ( "inline signature",
        "inline record",
        "bad.mli",
        "module M : sig type t = C of { x : int } [@@deriving %s] end" );
      ( "parameter implementation",
        "type parameters",
        "bad.ml",
        "module M = struct type 'a t = 'a list [@@deriving %s] end" );
      ( "parameter signature",
        "type parameters",
        "bad.mli",
        "module M : sig type 'a t = 'a list [@@deriving %s] end" );
      ( "function implementation",
        "not supported",
        "bad.ml",
        "module M = struct type t = int -> int [@@deriving %s] end" );
      ( "function signature",
        "not supported",
        "bad.mli",
        "module M : sig type t = int -> int [@@deriving %s] end" );
    ]
  in
  List.iter
    (fun mode ->
      List.iter
        (fun (label, expected, filename, template) ->
          let source = Printf.sprintf (Scanf.format_from_string template "%s") mode in
          match Ppx_yojson_minimal.Derive.process ~filename ~source with
          | Ok _ -> Alcotest.failf "%s/%s silently accepted" label mode
          | Error message ->
              Alcotest.(check bool) (label ^ "/" ^ mode) true (contains expected message))
        cases)
    [ "yojson"; "yojson_of" ]

let () =
  Alcotest.run "ppx native extensions"
    [
      ( "encoder-only",
        [
          Alcotest.test_case
            "nderive-s2lt u3ux 9atb 07js i3v2 cd80 p4tq e5va: compiled encoders/golden \
             JSON"
            `Quick test_encoders;
          Alcotest.test_case "nderive-s2lt 9atb p4tq: zero generated decoder surface"
            `Quick test_no_decoder_generation;
        ] );
      ( "ordinary modules",
        [
          Alcotest.test_case
            "nderive-i3v2 sfta cd80 p4tq ufnu e5va: compiled modules/golden JSON" `Quick
            test_modules;
          Alcotest.test_case
            "nderive-07js i3v2 e5va: unsupported contexts fail atomically" `Quick
            test_unsupported;
        ] );
    ]
