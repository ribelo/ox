(* ^nlet-q3z3 ^nlet-axvf: expansion shape, located refusals, untouched files. *)
open Ocaml_common

let expand source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf "input.ml";
  let ast = Parse.implementation lexbuf in
  let mapped = Ppx_ox_let.Expand.mapper.structure Ppx_ox_let.Expand.mapper ast in
  Format.asprintf "%a" Pprintast.structure mapped

let check_expansion name source expected () =
  Alcotest.(check string) name expected (expand source)

let untouched () =
  let source = "let x = 1\n(* no rewriting here *)\n" in
  match Ppx_ox_let.Expand.process ~filename:"plain.ml" ~source with
  | Ok output -> Alcotest.(check string) "byte-identical" source output
  | Error message -> Alcotest.fail message

let binary_ast () =
  match
    Ppx_ox_let.Expand.process ~filename:"bind.ml"
      ~source:"let f r = let%bind x = r in Ok x\n"
  with
  | Ok output ->
      let magic = Config.ast_impl_magic_number in
      Alcotest.(check string)
        "AST magic" magic
        (String.sub output 0 (String.length magic))
  | Error message -> Alcotest.fail message

let located_refusal () =
  match
    Ppx_ox_let.Expand.process ~filename:"user.ml" ~source:"let a = 1\nlet f = [%bind 1]\n"
  with
  | Ok _ -> Alcotest.fail "a %bind without let must be refused"
  | Error message ->
      let mentions needle =
        let n = String.length needle in
        let rec go i =
          i + n <= String.length message && (String.sub message i n = needle || go (i + 1))
        in
        go 0
      in
      Alcotest.(check bool)
        ("names the user's file and line: " ^ message)
        true
        (mentions "user.ml" && mentions "line 2")

let () =
  Alcotest.run "ppx_ox_let"
    [
      ( "expansion",
        [
          Alcotest.test_case "^nlet-q3z3 bind" `Quick
            (check_expansion "bind" "let f r = let%bind x = r in Ok (x + 1)"
               "let f r = ((Ox.Result.bind r (fun x -> Ok (x + 1)))[@nontail ])");
          Alcotest.test_case "^nlet-q3z3 map" `Quick
            (check_expansion "map" "let f r = let%map x = r in x + 1"
               "let f r = ((Ox.Result.map r (fun x -> x + 1))[@nontail ])");
          Alcotest.test_case "^nlet-q3z3 and" `Quick
            (check_expansion "and" "let f a b = let%bind x = a and y = b in Ok (x + y)"
               "let f a b = ((Ox.Result.bind (Ox.Result.both a b) (fun (x, y) -> Ok (x + \
                y)))\n\
               \  [@nontail ])");
          Alcotest.test_case "^nlet-axvf untouched" `Quick untouched;
          Alcotest.test_case "^nlet-axvf binary AST" `Quick binary_ast;
          Alcotest.test_case "^nlet-axvf located refusal" `Quick located_refusal;
        ] );
    ]
