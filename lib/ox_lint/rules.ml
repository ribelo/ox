(* ^nlint-hxar ^nlint-emql: the first typed rule, from the measured spike. *)
open Ocaml_common

type t = {
  id : string;
  message : string;
  violating : string;
  clean : string;
  documentation : string;
  source :
    ((Location.t -> unit) ->
    Syntax.context ->
    Ast_iterator.iterator ->
    Ast_iterator.iterator)
    option;
  typed : ((Location.t -> unit) -> Tast_iterator.iterator) option;
  evidence :
    (emit:(Location.t -> string -> unit) ->
    undecided:(Location.t -> string -> unit) ->
    Artifact.t ->
    unit)
    option;
}

let discarded_result = Disposal.discarded_result

(* ^nlintc-7be1: implementations may hide exceptions; signatures expose them. *)
let public_exception ~caps emit _context (base : Ast_iterator.iterator) =
  let contract = ref false in
  {
    base with
    module_type =
      (fun self m ->
        let saved = !contract in
        base.module_type self m;
        contract := saved);
    signature_item =
      (fun self item ->
        let saved = !contract in
        (match item.Parsetree.psig_desc with
        | Psig_modtype _ | Psig_modtypesubst _ -> contract := true
        | Psig_exception _ when not !contract ->
            if not (Caps_policy.private_module ~caps item.psig_loc.loc_start.pos_fname)
            then emit item.psig_loc
        | _ -> ());
        base.signature_item self item;
        contract := saved);
  }

(* ^ncapslint-nf4t ^ncapslint-snhg: one registry and one fixture/page triangle. *)
let basic_rule name message =
  let file = String.map (fun c -> if c = '-' then '_' else c) name in
  {
    id = "ox-" ^ name;
    message;
    violating = "test/lint/violating/" ^ file ^ ".ml";
    clean = "test/lint/clean/" ^ file ^ ".ml";
    documentation = "docs/rules/ox-" ^ name ^ ".md";
    source = None;
    typed = None;
    evidence = None;
  }

let concurrency_rule name message typed =
  { (basic_rule name message) with typed = Some typed }

(* ^safe-fr73 ^safe-y047: checked evidence can report uncertainty without a finding. *)
let evidence_rule name message evidence =
  { (basic_rule name message) with evidence = Some evidence }

let visit iterator artifact =
  match artifact.Artifact.info.cmt_annots with
  | Cmt_format.Implementation tree -> iterator.Tast_iterator.structure iterator tree
  | Cmt_format.Interface tree -> iterator.Tast_iterator.signature iterator tree
  | _ -> invalid_arg "complete checked annotation required"

let capability_rule ~caps name typed =
  {
    id = "ox-caps-" ^ name;
    message =
      (if name = "signature" then
         "dangerous operation without its capability in the function signature"
       else
         "dangerous " ^ name
         ^ " operation without matching signature authority (docs/caps.md)");
    violating =
      "test/caps/rules/violating/"
      ^ String.map (fun c -> if c = '-' then '_' else c) name
      ^ ".ml";
    clean =
      "test/caps/rules/clean/"
      ^ String.map (fun c -> if c = '-' then '_' else c) name
      ^ ".ml";
    documentation = "docs/rules/ox-caps-" ^ name ^ ".md";
    source = (if name = "signature" then None else Some (Caps.source ~caps name));
    typed = Some typed;
    evidence = None;
  }

(* ^nlintd-z5p5 ^nlintd-vneh: interfaces use the same fixture/page registry. *)
let interface_rule name message typed =
  let rule = concurrency_rule name message typed in
  {
    rule with
    violating = Filename.remove_extension rule.violating ^ ".mli";
    clean = Filename.remove_extension rule.clean ^ ".mli";
  }

let all ~caps =
  List.map
    (fun (op : Caps.operation) -> capability_rule ~caps op.name (Caps.raw ~caps op.name))
    Caps.operations
  @ [ capability_rule ~caps "signature" (Caps.signature ~caps) ]
  @ [
      {
        id = "ox-discarded-result";
        message =
          "discarded result; propagate, recover or map the named error, or name an \
           intentional best-effort discard and explain it";
        violating = "test/lint/violating/discard.ml";
        clean = "test/lint/clean/discard.ml";
        documentation = "docs/rules/ox-discarded-result.md";
        source = None;
        typed = Some (discarded_result ~caps);
        evidence = None;
      };
      {
        (basic_rule "identity-external"
           "unchecked %identity declaration; use a compiler-checked typed function")
        with
        source = Some Identity_external.source;
      };
      evidence_rule "transaction-runner"
        "operation uses the originating pool; use the callback transaction runner"
        (fun ~emit ~undecided artifact ->
          visit (Transaction_runner.check ~caps ~emit ~undecided) artifact);
      evidence_rule "monotonic-elapsed-time"
        "wall-clock value reaches an elapsed contract; use a monotonic clock"
        (fun ~emit ~undecided artifact ->
          visit (Monotonic_elapsed_time.check ~caps ~emit ~undecided) artifact);
      evidence_rule "execution-context"
        "known operation executes in the wrong Eio/native context"
        (fun ~emit ~undecided artifact ->
          visit (Execution_context.check ~caps ~emit ~undecided) artifact);
      {
        (evidence_rule "cancel-mask-scope"
           "known indefinite wait executes inside cancellation protection"
           (fun ~emit ~undecided artifact ->
             visit (Cancel_mask.check ~caps ~emit ~undecided) artifact))
        with
        clean = "test/lint/clean/cancel_mask.ml";
        violating = "test/lint/violating/cancel_mask.ml";
      };
      evidence_rule "raw-sql-construction" Raw_sql.message
        (fun ~emit ~undecided artifact ->
          visit (Raw_sql.check ~caps ~emit ~undecided) artifact);
      concurrency_rule "catch-all"
        "cancellation propagation unproven; re-raise or reify the original exception; \
         unresolved helpers and stores without a visible use remain findings"
        (Concurrency.catch_all ~caps);
      concurrency_rule "suspending-finalizer"
        "unprotected suspension in cleanup; wrap the suspension in Eio.Cancel.protect or \
         use Eio.Switch.on_release"
        (Concurrency.suspending_finalizer ~caps);
      concurrency_rule "stdlib-lock"
        "Stdlib mutex held across suspension; release before yielding or use Eio.Mutex"
        (Concurrency.stdlib_lock ~caps);
      concurrency_rule "raw-concurrency"
        "raw Eio concurrency; use Scope.fork @ once, Spawner.t or Ox.Mutex when rows \
         61/64/65 land"
        (Concurrency.raw_concurrency ~caps);
      {
        id = "ox-public-exception";
        message =
          "public exception; hide the exception and expose a result-returning boundary";
        violating = "test/lint/violating/public_exception.mli";
        clean = "test/lint/clean/public_exception.mli";
        documentation = "docs/rules/ox-public-exception.md";
        source = Some (public_exception ~caps);
        typed = None;
        evidence = None;
      };
      (let message =
         "unchecked Obj.magic* cast; use a typed representation outside the verified \
          affine adapter"
       in
       evidence_rule "obj-magic" message (fun ~emit ~undecided artifact ->
           let report loc = emit loc message in
           visit
             (Concurrency.obj_magic_artifact ~caps ~artifact ~undecided report)
             artifact));
      concurrency_rule "race-deadline"
        (* ^nmono-m4tg *)
        "use Ox.Timeout.timeout (wall clock) or Ox.Timeout.timeout_mono (monotonic \
         clock) for deadlines; race selects first success, race_first/Fiber.any select \
         first settlement (success or failure)"
        (Concurrency.race_deadline ~caps);
      interface_rule "val-behaviour"
        "resource-bearing val needs Suspension, Cancellation, Finalizers and Locking \
         sentences (docs/rules/interface-documentation.md)"
        (Interface_docs.behaviour ~caps);
      interface_rule "cancel-safety"
        "cancellable val needs Cancellation safety: safe to re-run / unsafe because data \
         is lost / unsafe because progress is lost \
         (docs/rules/interface-documentation.md)"
        (Interface_docs.cancel_safety ~caps);
    ]

(* No shipped exception paths; applicability is based on source kind only. *)
let allowances = []

(* ^nlintcov-r3k8 ^nlint-r01u: summary and applicability share the dormant policy. *)
let dormant ?(audit = false) rule =
  rule.id = "ox-raw-concurrency"
  || (not audit)
     && List.mem rule.id
          [
            "ox-transaction-runner";
            "ox-monotonic-elapsed-time";
            "ox-execution-context";
            "ox-cancel-mask-scope";
            "ox-raw-sql-construction";
          ]

let applies ?(audit = false) ~root ~source rule =
  let absolute path =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  let relative =
    let root = Caps_policy.policy_path (absolute root) in
    let source = Caps_policy.policy_path (absolute source) in
    if String.starts_with ~prefix:(root ^ "/") source then
      String.sub source
        (String.length root + 1)
        (String.length source - String.length root - 1)
    else source
  in
  (not (dormant ~audit rule))
  && (not (List.exists (fun (id, path, _) -> id = rule.id && path = relative) allowances))
  && ((not
         (List.mem rule.id
            [ "ox-public-exception"; "ox-val-behaviour"; "ox-cancel-safety" ]))
     || Filename.check_suffix source ".mli")

let select ~caps ids =
  let all = all ~caps in
  List.iter
    (fun id ->
      if not (List.exists (fun rule -> rule.id = id) all) then
        invalid_arg ("unknown rule " ^ id))
    ids;
  List.filter (fun rule -> ids = [] || List.mem rule.id ids) all

let self_check ~caps:_ ~root rules =
  List.concat_map
    (fun rule ->
      let missing field path =
        if
          path = ""
          || (not (Sys.file_exists (Filename.concat root path)))
          || Sys.is_directory (Filename.concat root path)
        then [ rule.id ^ ": missing " ^ field ^ " " ^ path ]
        else []
      in
      (if String.trim rule.message = "" then [ rule.id ^ ": missing replacement message" ]
       else [])
      @ missing "violating fixture" rule.violating
      @ missing "clean fixture" rule.clean
      @ missing "documentation" rule.documentation)
    rules
