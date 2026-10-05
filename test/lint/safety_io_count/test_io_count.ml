(* ^safe-jwwj ^safe-qmcw ^safe-t50j ^safe-fr73 ^safe-y047 ^safe-tlyw *)
open Ocaml_common

(* Expectations belong to the harness (docs/caps.md), not fixture attributes.
   These are one-based expression-start locations, including grouping parentheses.
   Formatting moved sites after attribute removal; this explicit table pins them. *)
let violating_sites =
  [
    ((2, 28), "stream");
    ((5, 11), "stream");
    ((9, 16), "stream");
    ((12, 28), "socket");
    ((15, 16), "socket");
    ((19, 20), "datagram");
    ((23, 25), "datagram");
    ((26, 35), "datagram");
    ((29, 11), "stream");
    ((33, 16), "stream");
    ((37, 34), "datagram");
    ((41, 36), "stream");
    ((45, 10), "stream");
    ((49, 10), "stream");
    ((52, 37), "stream");
    ((57, 37), "stream");
    ((61, 11), "stream");
    ((69, 20), "datagram");
    ((78, 38), "stream");
    ((79, 39), "stream");
    ((80, 28), "stream");
    ((83, 15), "stream");
    ((87, 15), "stream");
    ((92, 15), "stream");
    ((97, 24), "datagram");
    ((103, 16), "datagram");
    ((108, 15), "stream");
  ]

let warning_sites = [ ((16, 15), "socket"); ((20, 15), "stream") ]

let findings ~caps ~expected ?annotation name =
  let annotation =
    Option.value annotation
      ~default:
        ("fixtures/.io_count_fixtures.objs/byte/io_count_fixtures__" ^ name ^ ".cmt")
  in
  let artifact = Artifact.read ~caps annotation in
  Artifact.setup ~caps artifact;
  let found = ref [] in
  let iterator =
    Io_count.check ~caps ~emit:(fun loc message ->
        let start = loc.Location.loc_start in
        let site = (start.Lexing.pos_lnum, start.pos_cnum - start.pos_bol + 1) in
        found := (site, message) :: !found)
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> iterator.structure iterator tree
  | _ -> failwith "expected implementation");
  let actual = List.sort compare !found in
  let wanted = List.sort compare expected in
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
  let sites = List.map (fun (site, message) -> (site, classify message)) actual in
  (if sites <> wanted then
     let show xs =
       String.concat ";"
         (List.map
            (fun ((line, column), kind) -> Printf.sprintf "%d:%d:%s" line column kind)
            xs)
     in
     failwith
       (Printf.sprintf "%s: expected [%s], got [%s]" name (show wanted) (show sites)));
  actual

let () =
  let powerbox = Ox_test.powerbox () in
  let caps = (powerbox :> < Ox_caps.Cap.fs_read >) in
  ignore
    (findings ~caps ~expected:[]
       ~annotation:".io_count_pure.objs/byte/io_count_pure__Pure_case.cmt" "Pure_case");
  ignore (findings ~caps ~expected:violating_sites "Violating_case");
  ignore (findings ~caps ~expected:warning_sites "Warning_case");
  if findings ~caps ~expected:[] "Clean_case" <> [] then
    failwith "returned count is clean";
  ignore
    (findings ~caps ~expected:[]
       ~annotation:"../../../lib/test/.ox_test.objs/byte/ox_test.cmt" "Ox_test corpus")
