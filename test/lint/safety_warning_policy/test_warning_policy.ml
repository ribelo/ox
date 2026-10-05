(* ^safe-tpzm ^safe-y047: the partial-match compiler guard cannot be disabled. *)
open Warning_policy

let restriction label = function
  | Restriction _ -> ()
  | Clean | Unverified _ -> failwith label

let clean label = function
  | Clean -> ()
  | Restriction message | Unverified message -> failwith (label ^ ": " ^ message)

(* ^safe-tpzm: actual pinned compiler attached-attribute precedence, not floating strings. *)
let attached_parity specifications =
  let open Ocaml_common in
  let source =
    "let value = 1 "
    ^ String.concat " "
        (List.map
           (fun specification -> "[@@warning " ^ Printf.sprintf "%S" specification ^ "]")
           specifications)
  in
  let attributes =
    match Parse.implementation (Lexing.from_string source) with
    | [ { Parsetree.pstr_desc = Pstr_value (_, [ binding ]); _ } ] ->
        binding.pvb_attributes
    | _ -> failwith "expected attached attributes"
  in
  let guarded =
    Warnings.with_state (Warnings.backup ()) (fun () ->
        ignore (Warnings.parse_options false Warnings.defaults_w);
        ignore (Warnings.parse_options true "+a");
        Builtin_attributes.warning_scope attributes (fun () ->
            Warnings.is_active Warnings.All_clauses_guarded))
  in
  let decision =
    evaluate_attached ~inherited:[] (List.map (fun s -> (Warning, s)) specifications)
  in
  match (guarded, decision) with
  | true, Clean | false, Restriction _ -> ()
  | _ -> failwith ("attached attribute compiler parity: " ^ source)

let () =
  attached_parity [ "-8"; "+8" ];
  attached_parity [ "+8"; "-8" ];
  let recorded = [ "ocamlc"; "-warn-error"; "+a"; "-w"; "-P"; "-w"; "+8" ] in
  clean "literal Dune combined content agrees regardless of file timestamp"
    (reconcile ~recorded
       ~flags:(Some [ ":standard"; "-w"; "-P" ])
       ~compiler_flags:(Some [ "-w"; "+8" ]));
  (match
     reconcile ~recorded ~flags:(Some [ ":standard"; "-w"; "-8" ]) ~compiler_flags:None
   with
  | Unverified _ -> ()
  | _ -> failwith "changed Dune content must not trust preserved timestamp");
  (match
     reconcile ~recorded
       ~flags:(Some [ ":standard"; "-w"; "%{env:WARNINGS=+a}" ])
       ~compiler_flags:None
   with
  | Unverified _ -> ()
  | _ -> failwith "unresolved expansion must not trust recorded metadata");
  let open Ocaml_common in
  let witness = Warnings.Non_unit_statement in
  let snapshot () = (Warnings.is_active witness, Warnings.is_error witness) in
  let before = snapshot () in
  ignore (evaluate [ (Warning, "-a"); (Fatal, "-a") ]);
  ignore (evaluate [ (Warning, "not-valid?") ]);
  if snapshot () <> before then failwith "warning parser leaked compiler state";
  restriction "disabled partial-match must be a policy restriction"
    (evaluate [ (Warning, "-8") ]);
  clean "numeric and letter restoration have equivalent effective meaning"
    (evaluate [ (Warning, "-P+8"); (Fatal, "-8+P") ]);
  clean "whole-set restoration uses audited active and fatal sets"
    (evaluate [ (Warning, "-a"); (Warning, Ocaml_common.Warnings.defaults_w) ]);
  restriction "active borrowing warnings remain fatal in the root policy"
    (evaluate [ (Fatal, "-216") ]);
  clean "inactive default warnings need not become fatal" (evaluate [ (Fatal, "-32") ]);
  clean "stronger fatal alternative remains valid" (evaluate [ (Fatal, "+a") ]);
  restriction "named partial-match spelling preserves numeric meaning"
    (evaluate [ (Warning, "-partial-match") ]);
  clean "fatal @ restores both active and fatal compiler sets"
    (evaluate [ (Warning, "-8"); (Fatal, "@8") ]);
  clean "named restoration across ordered options"
    (evaluate [ (Warning, "-partial-match"); (Warning, "+partial-match") ]);
  restriction "required warning must stay fatal" (evaluate [ (Fatal, "-P") ]);
  restriction "all-warning disablement forbidden" (evaluate [ (Warning, "-a") ]);
  restriction "OxCaml borrowing guard is required" (evaluate [ (Warning, "-216") ]);
  restriction "unused local binding guard remains protected"
    (evaluate [ (Warning, "-26") ]);
  clean "root targeted unused-declaration controls remain baseline-equivalent"
    (evaluate [ (Warning, "-32-34-37") ]);
  match evaluate [ (Warning, "%{env:WARNINGS}") ] with
  | Unverified _ -> ()
  | Clean | Restriction _ -> failwith "unresolved specification must be named unverified"
