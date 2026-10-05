(* ^safe-jwwj ^safe-qmcw ^safe-t50j ^safe-fr73 ^safe-y047 ^safe-tlyw *)
open Ocaml_common

let findings ~caps ?annotation name =
  let annotation =
    Option.value annotation
      ~default:
        ("fixtures/.io_count_fixtures.objs/byte/io_count_fixtures__" ^ name ^ ".cmt")
  in
  let artifact = Artifact.read ~caps annotation in
  Artifact.setup ~caps artifact;
  let found = ref [] in
  let expected = ref [] in
  let base = Tast_iterator.default_iterator in
  let oracle =
    {
      base with
      expr =
        (fun self e ->
          List.iter
            (fun attr ->
              match attr.Parsetree.attr_name.txt with
              | "expect_stream" ->
                  expected :=
                    (e.Typedtree.exp_loc.Location.loc_start.Lexing.pos_lnum, "stream")
                    :: !expected
              | "expect_socket" ->
                  expected :=
                    (e.Typedtree.exp_loc.Location.loc_start.Lexing.pos_lnum, "socket")
                    :: !expected
              | "expect_datagram" ->
                  expected :=
                    (e.Typedtree.exp_loc.Location.loc_start.Lexing.pos_lnum, "datagram")
                    :: !expected
              | _ -> ())
            e.Typedtree.exp_attributes;
          base.expr self e);
    }
  in
  let iterator =
    Io_count.check ~caps ~emit:(fun loc message ->
        found := (loc.Location.loc_start.Lexing.pos_lnum, message) :: !found)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree ->
      oracle.structure oracle tree;
      iterator.structure iterator tree
  | _ -> failwith "expected implementation");
  let actual = List.sort compare !found in
  let wanted = List.sort compare !expected in
  let classify message =
    if String.starts_with ~prefix:"datagram" message then "datagram"
    else if String.starts_with ~prefix:"socket" message then "socket"
    else if String.starts_with ~prefix:"stream" message then "stream"
    else failwith ("unknown diagnostic: " ^ message)
  in
  List.iter
    (fun (_, message) ->
      match classify message with
      | "datagram"
        when not
               (String.ends_with ~suffix:"do not loop-until-full or split the message"
                  message) ->
          failwith "datagram repair must preserve one message"
      | "socket" when not (String.ends_with ~suffix:"never loop-until-full" message) ->
          failwith "unknown socket type must keep repairs conditional"
      | _ -> ())
    actual;
  let sites = List.map (fun (line, message) -> (line, classify message)) actual in
  (if sites <> wanted then
     let show xs =
       String.concat ";"
         (List.map (fun (line, kind) -> Printf.sprintf "%d:%s" line kind) xs)
     in
     failwith
       (Printf.sprintf "%s: expected [%s], got [%s]" name (show wanted) (show sites)));
  actual

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read >) in
  ignore
    (findings ~caps ~annotation:".io_count_pure.objs/byte/io_count_pure__Pure_case.cmt"
       "Pure_case");
  ignore (findings ~caps "Violating_case");
  ignore (findings ~caps "Warning_case");
  if findings ~caps "Clean_case" <> [] then failwith "returned count is clean";
  ignore
    (findings ~caps ~annotation:"../../../lib/test/.ox_test.objs/byte/ox_test.cmt"
       "Ox_test corpus")
