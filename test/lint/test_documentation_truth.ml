(* ^nlintd-truth ^nlintd-raises ^nlintd-cleanup *)
open Ocaml_common
open Ox_caps

let contains text needle =
  let rec loop i =
    i + String.length needle <= String.length text
    && (String.sub text i (String.length needle) = needle || loop (i + 1))
  in
  loop 0

let check ~caps directory =
  let source = directory ^ "/docs_truth.mli" in
  let artifact = Artifact.find ~caps source in
  Artifact.check ~caps ~source artifact;
  Artifact.setup ~caps artifact;
  let findings, undecided = (ref [], ref []) in
  Interface_docs.truth ~caps ~source ~artifact
    ~rules:[ "ox-val-behaviour"; "ox-cancel-safety" ]
    ~emit:(fun rule _ message -> findings := (rule, message) :: !findings)
    ~undecided:(fun _ message -> undecided := message :: !undecided);
  (List.rev !findings, List.rev !undecided)

let run ~caps =
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
  Cap_stdlib.print_endline ~caps
    "documentation truth: package reachability, relevant qualifications, raises, masking \
     and cancellation-path cleanup: pass"

let () = run ~caps:(Ox_caps_door.powerbox ())
