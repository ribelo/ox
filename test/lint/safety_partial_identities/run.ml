(* ^safe-3osb ^safe-35sb: nonempty compiler names; no fabricated identities or modes. *)
open Ocaml_common

(* ^safe-u7cx: evaluate compiler work and validate it even with -noassert. *)
let check condition = if not condition then failwith "compiler identity regression"

let paths caps =
  check (Paths.values ~caps [] = []);
  check (Paths.modules ~caps [] = []);
  check (Option.is_some (Paths.value ~caps ("Stdlib", [ "ignore" ])));
  check (Option.is_some (Paths.module_ ~caps ("Stdlib", [ "Result" ])));
  check (Paths.value ~caps ("Stdlib", [ "ox_missing_identity" ]) = None);
  check (Paths.module_ ~caps ("Ox_missing_module", []) = None);
  List.iter
    (fun ((head, tail) as name) ->
      match Longident.unflatten (head :: tail) with
      | None -> failwith "nonempty reference path unavailable"
      | Some expected -> check (Paths.lid name = expected))
    [
      ("x", []);
      ("Stdlib", [ "result" ]);
      ("Stdlib", [ "Result"; "value" ]);
      ("", []);
      ("", [ "" ]);
      ("A", [ ""; "b" ]);
      ("a.b", []);
      ("\\#type", []);
      ("A", [ "\\#let" ]);
    ]

let components () =
  List.iter
    (fun (text, first, last) ->
      check (Identity_docs.first_component text = first);
      check (Identity_docs.last_component text = last);
      match Longident.unflatten (String.split_on_char '.' text) with
      | None -> failwith "string split lacked its first component"
      | Some expected -> check (Paths.lid (Identity_docs.compiler_name text) = expected))
    [
      ("", "", "");
      (".", "", "");
      ("...", "", "");
      ("a", "a", "a");
      (".a", "", "a");
      ("a.", "a", "");
      ("A..b", "A", "b");
      ("A.B.C", "A", "C");
    ]

let decls source =
  match Parse.implementation (Lexing.from_string source) with
  | [ { Parsetree.pstr_desc = Pstr_type (_, declarations); _ } ] -> declarations
  | _ -> failwith "unexpected type fixture"

let groups () =
  let group source declarations =
    Identity_derive.group_of_decls ~source ~kind:Identity_derive.Structure ~recursive:true
      ~insert_at:(String.length source) declarations
  in
  check (group "" [] = None);
  let plain = "type t = int" in
  check (group plain (decls plain) = None);
  let inherited = "type a = int and b = string [@@deriving yojson]" in
  check (Option.is_some (group inherited (decls inherited)));
  let conflict =
    "type a = int [@@deriving yojson] and b = string [@@deriving yojson_of]"
  in
  check
    (Identity_derive.process ~filename:"conflict.ml" ~source:conflict
    = Error
        "conflict.ml: a type group cannot mix [@@deriving yojson] and [@@deriving \
         yojson_of]");
  check (Identity_derive.process ~filename:"empty.ml" ~source:"" = Ok "");
  check (Identity_derive.process ~filename:"plain.ml" ~source:plain = Ok plain)

let () =
  Compmisc.init_path ();
  let caps = Ox_caps_door.powerbox () in
  paths caps;
  components ();
  groups ();
  check (Identity_syntax.known_export ~caps "Stdlib" "ignore");
  check (Identity_syntax.known_export ~caps "Stdlib.Result" "value");
  check (not (Identity_syntax.known_export ~caps "Stdlib" ""))
