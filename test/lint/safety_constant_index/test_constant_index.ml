(* ^safe-rxya ^safe-d197 ^safe-xd2e ^safe-fr73 ^safe-y047 ^safe-czoe
   ^safe-tlyw ^safe-m5sp ^safe-t37w ^safe-12o2. *)
open Ocaml_common
open Typedtree

let expected =
  [
    ("upper", 1, 1, "array");
    ("escaped_upper", 2, 2, "string byte");
    ("unicode_upper", 2, 2, "string byte");
    ("empty_string", 0, 0, "string byte");
    ("negative_string", -1, 2, "string byte");
    ("array_empty", 0, 0, "array");
    ("array_negative", -1, 2, "array");
    ("module_alias", 1, 1, "array");
    ("opened", 1, 1, "string byte");
    ("value_alias", 1, 1, "string byte");
    ("bound_array", 1, 1, "array");
    ("bound_index", -1, 1, "string byte");
    ("bytes_upper", 2, 2, "bytes");
    ("bytes_empty", 0, 0, "bytes");
    ("bytes_negative", -1, 1, "bytes");
    ("bound_bytes", 1, 1, "bytes");
  ]

let run ~caps () =
  let source = "fixtures/fixture.ml" in
  let artifact =
    Artifact.read ~caps "fixtures/.constant_index_fixture.objs/byte/fixture.cmt"
  in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let tree =
    match artifact.info.cmt_annots with
    | Implementation tree -> tree
    | _ -> failwith "expected typed implementation fixture"
  in
  let owner loc =
    List.find_map
      (fun item ->
        match item.str_desc with
        | Tstr_value (_, bindings) ->
            List.find_map
              (fun binding ->
                if
                  binding.vb_loc.loc_start.pos_cnum <= loc.Location.loc_start.pos_cnum
                  && binding.vb_loc.loc_end.pos_cnum >= loc.loc_end.pos_cnum
                then
                  match binding.vb_pat.pat_desc with
                  | Tpat_var { id; _ } -> Some (Ident.name id)
                  | _ -> None
                else None)
              bindings
        | _ -> None)
      tree.str_items
    |> Option.get
  in
  let sites = ref [] in
  let iterator =
    Constant_index.check ~caps ~emit:(fun loc message ->
        sites := (owner loc, message) :: !sites)
  in
  let check () =
    sites := [];
    iterator.structure iterator tree;
    let actual = List.sort compare !sites in
    let expected =
      List.map
        (fun (name, index, length, kind) ->
          ( name,
            Printf.sprintf
              "constant index %d is outside [0, %d): proved %s length %d; indexing \
               raises a defect, not a result error"
              index length kind length ))
        expected
      |> List.sort compare
    in
    if actual <> expected then
      let show sites =
        String.concat "\n" (List.map (fun (name, message) -> name ^ ": " ^ message) sites)
      in
      failwith ("constant index expected:\n" ^ show expected ^ "\ngot:\n" ^ show actual)
  in
  check ();
  check ();
  Ox_caps.Cap_stdlib.print_endline ~caps "constant index typed decider: pass"

(* Review real compiled Ox sites through the same public visitor, before the
   shared rule registry has been integrated. Evidence exceptions stay fatal. *)
let scan ~caps paths =
  let findings = ref 0 in
  List.iter
    (fun path ->
      let artifact = Artifact.read ~caps path in
      let source = Artifact.source artifact in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact;
      let iterator =
        Constant_index.check ~caps ~emit:(fun loc message ->
            incr findings;
            Ox_caps.Cap_stdlib.printf ~caps "%s:%d: ox-constant-index: %s\n" source
              loc.Location.loc_start.Lexing.pos_lnum message)
      in
      match artifact.info.cmt_annots with
      | Implementation tree -> iterator.structure iterator tree
      | Interface tree -> iterator.signature iterator tree
      | _ -> failwith ("incomplete typed annotation " ^ path))
    paths;
  Ox_caps.Cap_stdlib.printf ~caps "Reviewed %d typed Ox modules: %d findings\n"
    (List.length paths) !findings;
  if !findings <> 0 then failwith "real Ox constant-index findings need migration"

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.stdout >) in
  match Array.to_list Sys.argv with
  | [ _ ] -> run ~caps ()
  | _ :: "--scan" :: (_ :: _ as paths) -> scan ~caps paths
  | _ -> failwith "usage: test_constant_index [--scan CMT...]"
