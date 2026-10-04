(* ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn *)
open Ocaml_common

let values directory fixture =
  let annotation =
    Printf.sprintf "%s/.concurrency_%s.objs/byte/concurrency_%s__%s.cmti" directory
      directory directory
      (String.capitalize_ascii fixture)
  in
  let source = directory ^ "/" ^ fixture ^ ".mli" in
  let artifact = Artifact.read annotation in
  Artifact.check ~source artifact;
  Artifact.setup artifact;
  let values = ref [] in
  let iterator = Interface_docs.iterator (fun value -> values := value :: !values) in
  (match artifact.info.cmt_annots with
  | Interface tree -> iterator.signature iterator tree
  | _ -> failwith "expected interface fixture");
  List.rev !values

let () =
  List.iter
    (fun (fixture, selector, expected) ->
      let bad = values "violating" fixture in
      let actual =
        List.filter_map
          (fun value ->
            if value.Interface_docs.families <> [] && not (selector value) then
              Some value.name
            else None)
          bad
      in
      if actual <> expected then failwith (fixture ^ ": got " ^ String.concat "," actual);
      let clean = values "clean" fixture in
      List.iter
        (fun value ->
          if value.Interface_docs.families <> [] && not (selector value) then
            failwith (fixture ^ " clean: " ^ value.name))
        clean)
    [
      ( "val_behaviour",
        (fun v -> v.Interface_docs.behaviour),
        [
          "missing";
          "nested";
          "flow";
          "incomplete";
          "dotted";
          "duplicate";
          "missing_period";
          "marker";
        ] );
      ( "cancel_safety",
        (fun v -> v.Interface_docs.cancel_safety),
        [ "receive"; "unknown"; "vague"; "Good.override"; "sibling"; "empty" ] );
    ];
  let clean = values "clean" "val_behaviour" in
  let selected =
    List.filter_map
      (fun value -> if value.Interface_docs.families = [] then None else Some value.name)
      clean
  in
  if
    selected
    <> [
         "with_default";
         "M.inherited";
         "M.override";
         "variant";
         "recursive";
         "mutex";
         "pool";
         "Protected.inside";
       ]
  then failwith ("typed selection: " ^ String.concat "," selected);
  print_endline
    "typed documentation shapes, aliases, recursive variants, records, pure lookalikes \
     and lexical defaults: pass"
