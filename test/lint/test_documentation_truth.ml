(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
open Ocaml_common
open Ox_caps

let contains text needle =
  let rec loop i =
    i + String.length needle <= String.length text
    && (String.sub text i (String.length needle) = needle || loop (i + 1))
  in
  loop 0

let check ~caps ?(name = "docs_truth") ?(rewrite = Fun.id) directory =
  let source = directory ^ "/" ^ name ^ ".mli" in
  let artifact = Artifact.find ~caps source in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let info =
    match artifact.info.cmt_annots with
    | Cmt_format.Interface signature ->
        { artifact.info with cmt_annots = Interface (rewrite signature) }
    | _ -> failwith "interface fixture did not supply a typed signature"
  in
  let artifact = { artifact with info } in
  let findings, undecided = (ref [], ref []) in
  Interface_docs.truth ~caps ~source ~artifact
    ~rules:[ "ox-val-behaviour"; "ox-cancel-safety" ]
    ~emit:(fun rule _ message -> findings := (rule, message) :: !findings)
    ~undecided:(fun _ message -> undecided := message :: !undecided);
  (List.rev !findings, List.rev !undecided)

(* ^nlintd-truth: missing shape claims alone must not force implementation evidence. *)
let check_unclaimed ~caps =
  let source = "violating/docs_truth.mli" in
  let artifact = Artifact.find ~caps source in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let info =
    match artifact.info.cmt_annots with
    | Cmt_format.Interface signature ->
        let sig_items =
          List.filter_map
            (fun item ->
              match item.Typedtree.sig_desc with
              | Tsig_attribute _ -> None
              | Tsig_value value ->
                  Some
                    { item with sig_desc = Tsig_value { value with val_attributes = [] } }
              | _ -> Some item)
            signature.sig_items
        in
        { artifact.info with cmt_annots = Interface { signature with sig_items } }
    | _ -> failwith "interface fixture did not supply a typed signature"
  in
  Interface_docs.truth ~caps ~source ~artifact:{ artifact with info }
    ~rules:[ "ox-val-behaviour"; "ox-cancel-safety" ]
    ~emit:(fun _ _ message -> failwith ("unclaimed truth finding: " ^ message))
    ~undecided:(fun _ message -> failwith ("unclaimed opaque evidence: " ^ message))

(* Substitute claims, never implementation behaviour or existing fixture assertions. ^nlintd-truth *)
let documentation text =
  let expression =
    Ast_helper.Exp.constant
      {
        Parsetree.pconst_desc = Pconst_string (text, Location.none, None);
        pconst_loc = Location.none;
      }
  in
  {
    Parsetree.attr_name = { txt = "ocaml.doc"; loc = Location.none };
    attr_payload = PStr [ Ast_helper.Str.eval expression ];
    attr_loc = Location.none;
  }

let only_document ?default name text signature =
  let items =
    List.filter_map
      (fun item ->
        match item.Typedtree.sig_desc with
        | Tsig_value value when value.val_name.txt = name ->
            Some
              {
                item with
                sig_desc =
                  Tsig_value { value with val_attributes = [ documentation text ] };
              }
        | Tsig_value _ | Tsig_attribute _ -> None
        | _ -> Some item)
      signature.Typedtree.sig_items
  in
  let sig_items =
    match (default, items) with
    | Some text, first :: _ ->
        { first with sig_desc = Tsig_attribute (documentation text) } :: items
    | _ -> items
  in
  { signature with sig_items }

let check_strict_claims ~caps =
  let rewrite =
    only_document "forward"
      "Suspension: never suspends because Eio.Fiber.yield has a ready slot. \
       Cancellation: not a cancellation point because Eio.Fiber.yield is ready. \
       Finalizers: none. Locking: none. Raises Eio.Cancel.Cancelled."
  in
  let findings, unknown = check ~caps ~rewrite "violating" in
  List.iter
    (fun witness ->
      if not (List.exists (fun (_, message) -> contains message witness) findings) then
        failwith ("unconditional yield escaped readiness disclosure: " ^ witness))
    [ "never suspends"; "no cancellation point" ];
  if unknown <> [] then
    failwith ("known yield became opaque: " ^ String.concat "\n" unknown);
  let rewrite =
    only_document "buffered_publish"
      "Suspension: never suspends because Eio.Stream.add has a reserved free slot. \
       Cancellation: not a cancellation point because Eio.Stream.add has a reserved free \
       slot; adds no cancellation check. Finalizers: none. Locking: internal stream \
       lock. Raises Eio.Cancel.Cancelled if the slot invariant is broken."
  in
  let findings, unknown = check ~caps ~rewrite "clean" in
  if not (List.exists (fun (_, message) -> contains message "no added Eio") findings) then
    failwith "readiness disclosure suppressed a strict no-added-check claim";
  if unknown <> [] then
    failwith ("known stream leaf became opaque: " ^ String.concat "\n" unknown);
  let default =
    "Cancellation and finalizers: Suspension: may suspend. Cancellation: propagates \
     Eio.Cancel.Cancelled. Cancellation safety: safe to re-run. Finalizers: none. \
     Locking: none."
  in
  let rewrite =
    only_document ~default "success_only"
      "Suspension: may suspend. Cancellation: propagates Eio.Cancel.Cancelled. \
       Cancellation safety: unsafe because progress is lost. Finalizers: closes the \
       channel only on success. Locking: delegated to Stdlib. Raises Invalid_argument \
       for a finished switch."
  in
  let findings, unknown = check ~caps ~rewrite "violating" in
  if findings <> [] || unknown <> [] then
    failwith
      ("overridden safety reappeared from lexical defaults: "
      ^ String.concat "\n" (List.map snd findings @ unknown))

(* ^nlintd-truth ^nlintcov-q6n2: fresh generated bodies are decided, not skipped. *)
let check_generated ~caps =
  let findings, unknown = check ~caps ~name:"docs_generated" "clean" in
  if findings <> [] || unknown <> [] then
    failwith ("generated truth evidence failed: " ^ String.concat "\n" unknown);
  let rewrite =
    only_document "forward" "Suspension: may suspend. @raise Failure always."
  in
  let findings, unknown = check ~caps ~name:"docs_generated" ~rewrite "clean" in
  if unknown <> [] then failwith "generated truth evidence became opaque";
  if not (List.exists (fun (_, message) -> contains message "@raise failure") findings)
  then failwith "generated implementation was not analysed"

(* ^nlintd-truth: one recursive node, distinct callback substitutions. *)
let check_recursive_applications ~caps =
  let rewrite =
    only_document "recursive_active"
      "Suspension: never suspends in Eio; effects of Stdlib operations depend on Stdlib \
       and are not checked. Cancellation: not a cancellation point; delegated Stdlib \
       calls add no Eio check. Finalizers: none. Locking: none."
  in
  let findings, unknown = check ~caps ~rewrite "clean" in
  if unknown <> [] then
    failwith ("finite recursive callback became opaque: " ^ String.concat "\n" unknown);
  List.iter
    (fun witness ->
      if not (List.exists (fun (_, message) -> contains message witness) findings) then
        failwith ("recursive callback lost its " ^ witness ^ " witness"))
    [ "never suspends"; "no cancellation point" ]

let run ~caps =
  check_recursive_applications ~caps;
  check_generated ~caps;
  check_unclaimed ~caps;
  check_strict_claims ~caps;
  (* Direct Eio leaf aliases must not become opaque compilation-unit edges. ^nlintd-truth *)
  let aliases, alias_unknown = check ~caps ~name:"docs_dependency" "clean" in
  if aliases <> [] || alias_unknown <> [] then
    failwith
      ("direct Eio alias truth: "
      ^ String.concat "\n" (List.map snd aliases @ alias_unknown));
  let clean, unknown = check ~caps "clean" in
  if clean <> [] || unknown <> [] then
    failwith ("clean truth fixture: " ^ String.concat "\n" (List.map snd clean @ unknown));
  let bad, unknown = check ~caps "violating" in
  List.iter
    (fun (name, witness) ->
      if
        not
          (List.exists
             (fun (_, message) -> contains message name && contains message witness)
             bad)
      then
        failwith
          ("missing truth mutation witness: " ^ name ^ " / " ^ witness ^ "\n"
          ^ String.concat "\n" (List.map snd bad @ unknown)))
    [
      ("fiber_spawn", "never suspends");
      ("fiber_spawn", "no cancellation point");
      ("domain_join", "never suspends");
      ("forward", "never suspends");
      ("forward", "no cancellation point");
      ("no_check", "no cancellation point");
      ("wrong_raise", "Failure");
      ("wrong_raise", "@raise invalid_argument");
      ("unattested", "@raise invalid_argument");
      ("success_only", "cleanup of resource");
      ("late_hook", "cleanup of resource");
      ("irrelevant_hook", "cleanup of resource");
      ("conditional_hook", "cleanup of resource");
      ("cancellable_finalizer", "cleanup of resource");
      ("partial_catch", "Invalid_argument");
      ("masked_added_check", "no added Eio");
      ("protected_cancellation", "cancellation can escape");
      ("swallowed_cancel", "cleanup of resource");
      ("operator_yield", "never suspends");
      ("result_operator_yield", "never suspends");
      ("saturated_partial", "never suspends");
      ("prefix_partial", "never suspends");
      ("recursive_prefix", "never suspends");
      ("recursive_prefix", "no cancellation point");
      ("callback_yield", "never suspends");
      ("optional_default_yield", "never suspends");
    ];
  if
    not
      (List.exists
         (fun message -> contains message "callback" && contains message "opaque call")
         unknown)
  then failwith ("opaque callback passed silently: " ^ String.concat "\n" unknown);
  if
    not
      (List.exists
         (fun message ->
           contains message "locking_only" && contains message "opaque call")
         unknown)
  then failwith "an unrelated locking delegation licensed a scheduling claim";
  List.iter
    (fun name ->
      if
        not
          (List.exists
             (fun message -> contains message name && contains message "opaque call")
             unknown)
      then failwith ("unresolved target passed silently: " ^ name))
    [ "functional_compare"; "unresolved_operator" ];
  if
    not
      (List.exists
         (fun message ->
           contains message "unqualified_input"
           && contains message "@raise end_of_file"
           && contains message "opaque calls")
         unknown)
  then failwith "an unnamed external raise source was treated as proof";
  if List.exists (fun message -> contains message "let-operator invocation") unknown then
    failwith "visible operator origin was replaced with a generic opacity";
  Cap_stdlib.print_endline ~caps
    "documentation truth: package reachability, relevant qualifications, raises, masking \
     and cancellation-path cleanup: pass"

let () = run ~caps:(Ox_caps_door.powerbox ())
