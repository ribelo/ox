(* OxCaml local mode annotations below are not parsed by ocamlformat 0.29.
   Keep this file in .ocamlformat-ignore until the formatter supports them. *)
module P = Protocol
module J = Jev_request

type observation = {
  snapshot : P.snapshot;
  text : string;
  can_scroll_down : bool;
  can_scroll_up : bool;
  fingerprint : string;
}

type handler = {
  observe : unit -> (observation, P.error) result;
  decide : J.request -> (J.decision, P.error) result;
  text_value : Text_helper.context -> (string option, P.error) result;
  act : observation -> J.decision -> text:string option -> (P.action_result, P.error) result;
}

(* drive-ls3c: what a type_text step needs before it acts. [Nothing] is every other
   operation and a dry run; [Value] is the text helper's answer, which the act writes; and
   [Missing] is the model's null — the value is missing — which ends the drive [blocked]
   naming the field. *)
type wanted = Nothing | Value of string | Missing of string

(* Each operation has an internal callback and a local-only public use. A token cannot
   escape the dynamic extent of run; even a nested drive has its own effect constructors. *)
type token = {
  observe : unit -> (observation, P.error) result;
  decide : J.request -> (J.decision, P.error) result;
  text_value : Text_helper.context -> (string option, P.error) result;
  act : observation -> J.decision -> string option -> (P.action_result, P.error) result;
}
let observe (t : token @ local) () = t.observe ()
let decide (t : token @ local) request = t.decide request
let text_value (t : token @ local) context = t.text_value context
let act (t : token @ local) page choice text = ((t.act page) choice) text

let operation name = match P.Operation.of_string name with Ok x -> x | Error _ -> assert false
let op_name = P.Operation.to_string
let status name = match P.Drive_status.of_string name with Ok x -> x | Error _ -> assert false
let internal message =
  let code =
    match P.Error_code.of_string "internal" with Ok x -> x | Error _ -> assert false
  in
  P.make_error code ~message
let ms seconds = max 0 (int_of_float (seconds *. 1000.))
(* drive-y7v8: an error names its cause, so the agent reading the trace knows whether
   to hand off, retry, or give up. *)
let failed what (error : P.error) =
  Printf.sprintf "%s failed (%s): %s" what
    (P.Error_code.to_string error.P.code)
    error.P.message

(* drive-n3ld: the dialog itself is in the final snapshot dialog field in full; the
   reason names its kind. Popups are the caller tabs to list; the reason counts them. *)
let dialog_reason (dialog : P.dialog) =
  "dialog open: " ^ P.Dialog_kind.to_string dialog.P.kind

let popup_reason popups =
  match List.length popups with
  | 1 -> "1 popup opened"
  | n -> Printf.sprintf "%d popups opened" n
let history (step : P.step) changed =
  J.{ action = op_name step.operation;
      kind = Some (if step.operation = operation "type_text" then "fill"
                   else if step.operation = operation "scroll_up" || step.operation = operation "scroll_down" then "scroll"
                   else op_name step.operation);
      text = step.text; page_changed = Some changed }

(* fly-hc3l, fly-4mio, fly-9e0f: predictions and executed input have separate
   budgets. A decision is consumed exactly once; stale input is not an action. *)
type page_label = { kind : string; source : string; url : string }

let loop (t : token) ~now ~model ~(args : P.drive_args) ~dry_run
    ~validate ~coverage ~usage ~telemetry ~observe_attempts ~recent:initial_recent
    ~scripts ~run_script ~on_step ~label =
  let started = now () in
  let deadline = started +. float_of_int (Option.value ~default:120 args.P.deadline_s) in
  let cap = Option.value ~default:60 args.P.max_steps in
  let actions = ref 0 and predictions = ref 0 and text_calls = ref 0 in
  let observations = ref 0 and observation_retries = ref 0 and stale = ref 0 in
  let observation_ms = ref 0 and prediction_ms = ref 0 and helper_ms = ref 0 and input_ms = ref 0 in
  let prediction_log = ref [] and text_log = ref [] and action_log = ref [] in
  let pending_text = ref None in
  (* map-op12: target identity survives snapshot refresh/reindexing, but never a
     page change. A no-op masks only its operation, not every action on that row. *)
  let mask_page = ref None and masked = ref [] in
  let targets (page : observation) =
    let rec identities seen = function
      | [] -> []
      | (row : P.row) :: rest ->
          let label = row.role, row.name in
          let rank = List.length (List.filter ((=) label) seen) in
          (row.index, (row.role, row.name, rank)) :: identities (label :: seen) rest in
    identities [] page.snapshot.rows in
  let mask_choice (page : observation) (choice : J.decision) =
    if not (List.mem (op_name choice.operation) ["wait"; "done"; "blocked"]) then (
      let target = Option.bind choice.index (fun index -> List.assoc_opt index (targets page)) in
      mask_page := Some page.fingerprint;
      let key = (choice.operation, target) in
      if not (List.mem key !masked) then masked := key :: !masked) in
  (* map-op12: menu toggles change the DOM fingerprint, not the target row set.
     Once masked, an oscillating action stays masked for this URL. *)
  let oscillation_url = ref None and oscillating = ref [] in
  let executions = Hashtbl.create 16 in
  let reset_oscillation (page : observation) =
    if !oscillation_url <> Some page.snapshot.url then (
      oscillation_url := Some page.snapshot.url;
      oscillating := []; Hashtbl.clear executions) in
  let row_set (page : observation) (role, name, _) =
    page.snapshot.rows |> List.filter_map (fun (row : P.row) ->
      if row.role = role && row.name = name then Some (row.value, row.options) else None)
    |> List.sort compare in
  let track_execution page next (choice : J.decision) =
    reset_oscillation page;
    match Option.bind choice.index (fun index -> List.assoc_opt index (targets page)) with
    | Some target when page.snapshot.url = next.snapshot.url ->
        let key = choice.operation, Some target in
        let rows = row_set next target in
        let previous, count = Option.value ~default:(rows, 0) (Hashtbl.find_opt executions key) in
        let count = if previous = rows && row_set page target = rows then count + 1 else 0 in
        Hashtbl.replace executions key (rows, count);
        if count >= 3 && not (List.mem key !oscillating) then oscillating := key :: !oscillating
    | _ -> () in
  let masks (page : observation) =
    reset_oscillation page;
    if !mask_page <> Some page.fingerprint then (mask_page := None; masked := []);
    List.concat_map (fun (op, target) -> match target with
      | None -> [op, None]
      | Some target -> List.filter_map (fun (index, identity) ->
          if identity = target then Some (op, Some index) else None)
          (targets page)) (!masked @ !oscillating) in
  (* fly-vnf1: BLOCKED cannot certify an unseen scroll frontier. This deliberate
     deviation from jev-ultrafast is bounded per URL. pbk-eyya raised the bound from three
     to eight: a 20-card listing is taller than three viewports, and JEV gave up on the
     pager of books.toscrape.com's Default category before seeing it. *)
  (* map-op08 map-bjon: a first viewport is not a complete collection. *)
  let exhaustive =
    (let words = String.lowercase_ascii args.goal in
     List.exists (fun word -> try ignore (Str.search_forward (Str.regexp_string word) words 0); true with Not_found -> false) ["collect"; "extract"; "list"; "gather"])
    && (try ignore (Str.search_forward (Str.regexp "\\b\\(every\\|all\\)\\b")
         (String.lowercase_ascii args.goal) 0); true with Not_found -> false) in
  let done_refusals = ref 0 in
  let collection_frontier (page : observation) =
    if page.can_scroll_down then Some "the page can still scroll down"
    else if List.exists (fun (row : P.row) ->
      List.mem row.role ["link"; "button"]
      && not (List.exists (fun state -> P.Row_state.to_string state = "disabled")
                (Option.value ~default:[] row.state))
      && List.mem (String.lowercase_ascii (String.trim row.name))
           ["next"; "next page"; "next ›"; "next »"; "›"; "»"])
      page.snapshot.rows then Some "a next-page row is still available"
    else None in
  let rescue_cap = 8 in
  let frontiers = Hashtbl.create 8 in
  let integer n = `Int n and string s = `String s in
  let optional_string = function None -> `Null | Some s -> string s in
  let optional_int = function None -> `Null | Some n -> integer n in
  let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None in
  let measured total fn =
    let at = now () in
    let answer = fn () in
    total := !total + ms (now () -. at);
    answer
  in
  let observe_page () =
    let rec attempt left =
      incr observations;
      match measured observation_ms (fun () -> observe t ()) with
      | Error error when P.Error_code.to_string error.code = "stale-snapshot" && left > 1 && now () < deadline ->
          incr observation_retries; attempt (left - 1)
      | answer -> answer
    in
    attempt observe_attempts
  in
  let finish ?reason ?error name steps (page : observation) =
    let status = status name in
    let extra = telemetry () in
    let metric key fallback = Option.value ~default:(integer fallback) (member key extra) in
    let bounds = coverage page in
    let text_truncated = Option.value ~default:(`Bool (String.length page.text >= 6000)) (member "text_truncated" bounds) in
    let omitted_elements = Option.value
      ~default:(integer (max 0 (page.snapshot.total - List.length page.snapshot.rows)))
      (member "omitted_elements" bounds) in
    let metrics = `Assoc [
      "actions", integer !actions; "predictions", integer !predictions;
      "text_calls", integer !text_calls; "observation_calls", metric "observation_calls" !observations;
      "observation_retries", metric "observation_retries" !observation_retries;
      "stale_decisions", integer !stale; "bootstrap_ms", metric "bootstrap_ms" 0;
      "observation_ms", integer !observation_ms; "prediction_ms", integer !prediction_ms;
      "text_helper_ms", integer !helper_ms; "input_ms", metric "input_ms" !input_ms;
      "settle_ms", metric "settle_ms" 0; "elapsed_ms", integer (ms (now () -. started)) ] in
    let shown =
      if Page_kind.is_page ~url:page.snapshot.url then
        Option.map (fun label -> label ~url:page.snapshot.url ~title:page.snapshot.title ~text:page.text) label
      else None in
    let state = `Assoc [
      "status", string name; "reason", optional_string reason;
      "error", (match error with None -> `Null | Some error -> P.yojson_of_error error);
      "initial_recent_actions", `List (List.map J.yojson_of_recent_action initial_recent);
      "page", `Assoc [ "snapshot", P.yojson_of_snapshot page.snapshot;
        (* trace-qe8c kind-ir9l: only model requests substitute the kind. *)
        "url", string page.snapshot.url;
        "title", string page.snapshot.title;
        "page_kind", (match shown with Some shown -> string shown.kind | None -> `Null);
        "page_kind_source", (match shown with Some shown -> string shown.source | None -> `Null);
        "text", string page.text; "text_truncated", text_truncated;
        "omitted_elements", omitted_elements;
        "unsupported_states", Option.value ~default:(`List []) (member "unsupported_states" bounds);
        "can_scroll_down", `Bool page.can_scroll_down; "can_scroll_up", `Bool page.can_scroll_up;
        "coverage", Option.value ~default:(string "viewport") (member "coverage" bounds);
        "bounds", bounds ];
      "history", `List (List.rev !action_log);
      "predictions", `List (List.rev !prediction_log);
      "text_calls", `List (List.rev !text_log); "metrics", metrics ] in
    Ok P.{ status; steps = List.rev steps; final = page.snapshot; reason; operator_state = Some state }
  in
  let context page choice recent =
    match choice.J.index with
    | None -> Error (internal "a type_text decision names no field")
    | Some index ->
        (match List.find_opt (fun (element : J.element) ->
             element.row = index && List.mem (operation "type_text") element.operations)
           (J.elements page.snapshot) with
         | None -> Error (internal (Printf.sprintf "row %d is not a compatible text field" index))
         | Some element -> Ok Text_helper.{ goal = args.P.goal;
             field = { label = element.label; role = element.role; value = element.value };
             page_title = page.snapshot.title; page_text = page.text; recent = List.rev recent })
  in
  let stale_error error = P.Error_code.to_string error.P.code = "stale-snapshot" in
  let update_prediction outcome =
    match !prediction_log with
    | `Assoc fields :: rest -> prediction_log := `Assoc (("outcome", string outcome) :: List.remove_assoc "outcome" fields) :: rest
    | _ -> ()
  in
  (* field-5sdo: a password row's value is never a trace field, even if a step
     typed one. The operator does not type passwords; this is the backstop. *)
  let redact_password (page : observation) index text =
    match (index, text) with
    | Some index, Some _ -> (
        match List.find_opt (fun (row : P.row) -> row.index = index) page.snapshot.rows with
        | Some row -> (
            match row.state with
            | Some states
              when List.exists (fun state -> P.Row_state.to_string state = "password") states
              ->
                Some "[password]"
            | _ -> text)
        | None -> text)
    | _ -> text
  in
  let record_step (page : observation) (next : observation) choice text steps =
    let text = redact_password page choice.J.index text in
    let recorded = P.{
        non_repeatable = Playbook.non_repeatable_action
          ~context:(Playbook.action_risk_context ~snapshot:page.snapshot ~text:page.text ~index:choice.J.index)
          (P.Operation.to_string choice.J.operation);
        n = List.length steps + 1; snapshot = page.snapshot.snapshot;
        operation = choice.J.operation; index = choice.index;
        probabilities = J.trace_probabilities choice;
        target = Option.bind choice.index (fun index ->
          Option.map (fun (row : P.row) -> P.{ target_role = row.role; target_label = row.name })
            (List.find_opt (fun (row : P.row) -> row.index = index) page.snapshot.rows)); text;
        after = { url = next.snapshot.url; title = next.snapshot.title };
        elapsed_ms = ms (now () -. started) } in
    on_step recorded; recorded
  in
  match observe_page () with
  | Error error -> Error error
  | Ok first ->
      let rec go page steps recent =
        let rescue_count, seen_top, seen_bottom =
          Option.value ~default:(0, false, false) (Hashtbl.find_opt frontiers page.snapshot.url) in
        let seen_top = seen_top || not page.can_scroll_up in
        let seen_bottom = seen_bottom || not page.can_scroll_down in
        Hashtbl.replace frontiers page.snapshot.url (rescue_count, seen_top, seen_bottom);
        if now () >= deadline then finish ~reason:"caller deadline exhausted" "deadline" steps page
        else if !predictions >= 2 * cap then
          finish ~reason:(Printf.sprintf "prediction budget exhausted (%d predictions)" (2 * cap)) "step-cap" steps page
        else if page.snapshot.dialog <> None then
          finish ?reason:(Option.map dialog_reason page.snapshot.dialog) "error" steps page
        else
          let request = J.make ~model ~goal:args.goal ~snapshot:page.snapshot ~text:page.text
            ~recent:(List.rev recent) ~can_scroll_down:page.can_scroll_down ~can_scroll_up:page.can_scroll_up
            |> fun request -> J.without_actions request (masks page)
            |> fun request -> J.with_scripts request (scripts page)
            |> fun request -> J.with_coverage request (coverage page)
            |> fun request ->
              match label with
              | None -> request
              | Some label ->
                  let shown = label ~url:page.snapshot.url ~title:page.snapshot.title ~text:page.text in
                  if shown.url = page.snapshot.url then request else J.with_shown_url request shown.url in
          let at = now () in
          incr predictions;
          match measured prediction_ms (fun () -> decide t request) with
          | Error error ->
              prediction_log := `Assoc [ "n", integer !predictions;
                "snapshot", string (P.Snapshot_id.to_string page.snapshot.snapshot);
                "operation", `Null; "index", `Null; "option", `Null;
                "probabilities", `Null; "confidence", `Null;
                "outcome", string "provider-error"; "error", P.yojson_of_error error;
                "usage", Option.value ~default:`Null (usage "operator");
                "elapsed_ms", integer (ms (now () -. at)) ] :: !prediction_log;
              finish ~error ~reason:(failed "JEV prediction" error) "error" steps page
          | Ok choice ->
              let op = choice.J.operation in
              let model_operation = op_name op in
              let offered name = List.exists (fun (key, _) -> String.uppercase_ascii key = name) choice.operation_probabilities in
              let rescue =
                if op <> operation "blocked" || rescue_count >= rescue_cap || !actions >= cap then None
                else if not seen_bottom && page.can_scroll_down && offered "SCROLL_DOWN" then Some (operation "scroll_down")
                else if not seen_top && page.can_scroll_up && offered "SCROLL_UP" then Some (operation "scroll_up")
                else None in
              prediction_log := `Assoc [ "n", integer !predictions;
                "snapshot", string (P.Snapshot_id.to_string page.snapshot.snapshot);
                "operation", string (match choice.J.script with
                  | Some name -> J.run_script_prefix ^ name
                  | None -> op_name op);
                "index", optional_int choice.index;
                "option", optional_int choice.option;
                "probabilities", P.yojson_of_probabilities (J.trace_probabilities choice);
                "confidence", `Float choice.confidence; "outcome", string "predicted";
                "rescued_operation", (match rescue with None -> `Null | Some op -> string (op_name op));
                "usage", Option.value ~default:`Null (usage "operator");
                "elapsed_ms", integer (ms (now () -. at)) ] :: !prediction_log;
              let choice = match rescue with None -> choice | Some operation ->
                { choice with J.operation; index = None; option = None; target_confidence = None;
                  target_probabilities = []; targets = [] } in
              let op = choice.J.operation in
              let terminal =
                choice.J.script = None && (op = operation "done" || op = operation "blocked") in
              let refresh ?(recent = recent) why =
                incr stale;
                update_prediction why;
                match observe_page () with
                | Error error -> finish ~error ~reason:(failed "refresh stale observation" error) "error" steps page
                | Ok next -> go next steps recent
              in
              if now () >= deadline then finish ~reason:"caller deadline exhausted after prediction; no input" "deadline" steps page
              else if dry_run then
                let step = record_step page page choice None steps in
                update_prediction "dry-run; no input";
                finish ~reason:"dry run: the proposed action was not dispatched" "blocked" (step :: steps) page
              else if Option.is_some choice.J.script then
              let name = Option.get choice.J.script in (
                  match run_script with
                  | None ->
                      finish ~reason:"internal: a script was chosen without a runner" "error" steps page
                  | Some run_script -> (
                      match run_script ~url:page.snapshot.url name with
                      | Error error ->
                          update_prediction "script error";
                          finish ~error ~reason:(failed "run_script" error) "error" steps page
                      | Ok (J.Script_blocked { argument }) ->
                          update_prediction "missing argument; no input";
                          finish ~reason:(Printf.sprintf "no value for argument %S" argument) "blocked" steps page
                      | Ok (J.Script_continue { summary }) -> (
                          update_prediction "script";
                          match observe_page () with
                          | Error error ->
                              finish ~error ~reason:(failed "observe after script" error) "error" steps page
                          | Ok next ->
                              let changed = page.fingerprint <> next.fingerprint in
                              let recent =
                                J.{ action = summary; kind = Some "script"; text = None; page_changed = Some changed }
                                :: recent
                              in
                              if J.stalled (List.rev recent) then
                                finish ~reason:"the operator repeated three non-WAIT actions without changing the page" "blocked" steps next
                              else go next steps recent)))
              else if not terminal && !actions >= cap then (
                update_prediction "action budget; no input";
                finish ~reason:(Printf.sprintf "action budget exhausted (%d executed actions)" cap) "step-cap" steps page)
              else
                let checked = if terminal || op = operation "type_text" then validate page else Ok () in
                match checked with
                | Error error when stale_error error -> refresh "stale; no input"
                | Error error -> finish ~error ~reason:(failed "validate observation" error) "error" steps page
                | Ok () when terminal ->
                    (* fly-vzzw: never accept an old terminal opinion, even after the last action. *)
                    (match observe_page () with
                     | Error error -> finish ~error ~reason:(failed "fresh terminal observation" error) "error" steps page
                     | Ok next when page.fingerprint <> next.fingerprint ->
                         incr stale; update_prediction "stale terminal; re-decide"; go next steps recent
                     | Ok next when op = operation "done" && exhaustive
                                    && Option.is_some (collection_frontier next) ->
                         let reason = "collection DONE refused: " ^ Option.get (collection_frontier next) in
                         update_prediction reason;
                         if !done_refusals >= 3 then
                           finish ~reason:(reason ^ "; three refusals exhausted") "blocked" steps next
                         else (
                           incr done_refusals;
                           go next steps (J.{ action = reason; kind = Some "guard";
                             text = None; page_changed = None } :: recent))
                     | Ok next ->
                         update_prediction "terminal";
                         let step = record_step page next choice None steps in
                         if op = operation "done" then finish "done" (step :: steps) next
                         else
                            let reason = match member "unsupported_states" (coverage next) with
                              | Some (`List states) when List.mem (`String "password-field") states ->
                                  (* daily-9ggi fly-eoqg: the operator never types a password; the
                                     agent does, with leash fill on the row snap marks password. *)
                                  "the page needs a password, which the operator never types: fill it with `leash fill` (snap marks the row password), then drive the rest"
                              | Some (`List (_ :: _ as states)) ->
                                  "the operator found no available action; unsupported visible UI: " ^
                                  String.concat ", " (List.filter_map (function `String name -> Some name | _ -> None) states)
                              | _ -> "the operator found no available action toward the goal" in
                            finish ~reason "blocked" (step :: steps) next)
                | Ok () ->
                    let wanted =
                      if op <> operation "type_text" then Ok Nothing
                      else match context page choice recent with
                        | Error error -> Error error
                        | Ok context ->
                            let at = now () in
                            let answer, called = match !pending_text with
                              | Some (old_context, value) when old_context = context -> Ok (Some value), false
                              | _ ->
                                  incr text_calls;
                                  let answer = measured helper_ms (fun () -> text_value t context) in
                                  (match answer with Ok (Some value) -> pending_text := Some (context, value) | _ -> ());
                                  answer, true in
                            if called then text_log := `Assoc [ "field", string context.Text_helper.field.label;
                              "value", (match answer with Ok value -> optional_string value | Error _ -> `Null);
                              "outcome", string (match answer with Ok (Some _) -> "value" | Ok None -> "missing value" | Error _ -> "provider-error");
                              "usage", Option.value ~default:`Null (usage "text_helper");
                              "elapsed_ms", integer (ms (now () -. at)) ] :: !text_log;
                            match answer with
                            | Ok (Some text) -> Ok (Value text)
                            | Ok None -> Ok (Missing context.field.label)
                            | Error error -> Error error
                    in
                    match wanted with
                    | Error error -> finish ~error ~reason:(failed "TYPE_TEXT helper" error) "error" steps page
                    | Ok (Missing field) ->
                        update_prediction "missing field; no input";
                        let step = record_step page page choice None steps in
                        finish ~reason:(Printf.sprintf "no value for field %S" field) "blocked" (step :: steps) page
                    | Ok wanted ->
                        let text = match wanted with Value text -> Some text | Nothing -> None | Missing _ -> assert false in
                        if now () >= deadline then finish ~reason:"caller deadline exhausted after helper; no input" "deadline" steps page
                        else
                          let before_telemetry = telemetry () in
                          let at = now () in
                          let answer = measured input_ms (fun () -> act t page choice text) in
                          match answer with
                          | Error error when stale_error error -> refresh "stale; no input"
                          (* map-op07: an action refused before dispatch sent no input. Re-observe
                             and let JEV decide again; do not end as outcome uncertain. *)
                          | Error error
                            when P.Error_code.to_string error.P.code = "row-not-actionable" ->
                              mask_choice page choice;
                              let recent = J.{ action = error.message; kind = Some "guard";
                                text = None; page_changed = None } :: recent in
                              refresh ~recent ("refused; no input: " ^ error.message)
                          | Error error ->
                              update_prediction "input outcome uncertain; not replayed";
                              let step = record_step page page choice text steps in
                              action_log := `Assoc [ "step", P.yojson_of_step step;
                                "option", optional_int choice.option; "outcome", string "uncertain; not replayed";
                                "page_changed", `Null; "input_ms", integer (ms (now () -. at));
                                "settle_ms", integer 0 ] :: !action_log;
                              finish ~error ~reason:(failed ("the " ^ op_name op ^ " action (outcome uncertain; not replayed)") error) "error" (step :: steps) page
                          | Ok acted ->
                              incr actions; pending_text := None; update_prediction "executed";
                              if rescue <> None then
                                Hashtbl.replace frontiers page.snapshot.url (rescue_count + 1, seen_top, seen_bottom);
                              (* fly-4mio: record confirmed execution before a fallible observation. *)
                              let step = record_step page page choice text steps in
                              let acknowledged_ms = ms (now () -. at) in
                              let action_fields () =
                              let after_telemetry = telemetry () in
                              let delta key fallback = match member key before_telemetry, member key after_telemetry with
                                | Some (`Int before), Some (`Int after) -> integer (max 0 (after - before))
                                | _ -> integer fallback in
                              [ "option", optional_int choice.option; "outcome", string "executed";
                                "model_operation", string model_operation; "rescue", `Bool (rescue <> None);
                                "input_ms", delta "input_ms" acknowledged_ms; "settle_ms", delta "settle_ms" 0 ] in
                              action_log := `Assoc (("step", P.yojson_of_step step) :: ("page_changed", `Null) :: action_fields ()) :: !action_log;
                              (match observe_page () with
                               | Error error ->
                                    action_log := `Assoc (("step", P.yojson_of_step step) :: ("page_changed", `Null) :: action_fields ()) :: List.tl !action_log;
                                    finish ~error ~reason:(failed "observe after executed action; not replayed" error) "error" (step :: steps) page
                               | Ok next ->
                                   let step = record_step page next choice text steps in
                                   track_execution page next choice;
                                   if page.fingerprint = next.fingerprint then mask_choice page choice;
                                   let changed = page.fingerprint <> next.fingerprint in
                                   action_log := `Assoc (("step", P.yojson_of_step step) :: ("page_changed", `Bool changed) :: action_fields ()) :: List.tl !action_log;
                                   let steps = step :: steps in
                                   let recent = history step changed :: recent in
                                   match acted.dialog, acted.popups with
                                   | Some dialog, _ -> finish ~reason:(dialog_reason dialog) "error" steps next
                                   | None, _ :: _ -> finish ~reason:(popup_reason acted.popups) "error" steps next
                                   | None, [] when J.stalled (List.rev recent) ->
                                       finish ~reason:"the operator repeated three non-WAIT actions without changing the page" "blocked" steps next
                                   | None, [] -> go next steps recent)
      in
      go first [] (List.rev initial_recent)

let run ?(on_step = fun (_ : P.step) -> ()) ?(validate = fun _ -> Ok ()) ?(coverage = fun _ -> `Assoc [])
    ?(usage = fun _ -> None) ?(telemetry = fun () -> `Assoc []) ?(observe_attempts = 10) ?(recent = [])
    ?(scripts = fun _ -> []) ?run_script ?label
    ~(handler : handler) ~now ~model ~(args : P.drive_args) ~dry_run () =
  if Option.value ~default:60 args.P.max_steps < 1 ||
     Option.value ~default:120 args.deadline_s < 1 || observe_attempts < 1 || observe_attempts > 10 then
    Error
      (P.make_error
         (match P.Error_code.of_string "invalid-request" with
         | Ok x -> x
         | Error _ -> assert false)
         ~message:"drive max_steps and deadline_s must be positive; observe_attempts must be 1..10")
  else
    let module M = struct
      type _ Effect.t += Observe : (observation, P.error) result Effect.t
      type _ Effect.t += Decide : J.request -> (J.decision, P.error) result Effect.t
      type _ Effect.t += Text : Text_helper.context -> (string option, P.error) result Effect.t
      type _ Effect.t += Act : observation * J.decision * string option -> (P.action_result, P.error) result Effect.t
    end in
    let token = {
      observe = (fun () -> Effect.perform M.Observe);
      decide = (fun request -> Effect.perform (M.Decide request));
      text_value = (fun context -> Effect.perform (M.Text context));
      act = (fun page choice text -> Effect.perform (M.Act (page, choice, text)));
    } in
    Effect.Deep.match_with (fun () -> loop token ~now ~model ~args ~dry_run ~validate ~coverage ~usage ~telemetry ~observe_attempts ~recent ~scripts ~run_script ~on_step ~label) ()
      { retc = Fun.id; exnc = raise;
        effc = (fun (type a) (eff : a Effect.t) -> match eff with
          | M.Observe -> Some (fun (k : (a, (P.drive_result, P.error) result) Effect.Deep.continuation) -> Effect.Deep.continue k (handler.observe ()))
          | M.Decide request -> Some (fun (k : (a, (P.drive_result, P.error) result) Effect.Deep.continuation) -> Effect.Deep.continue k (handler.decide request))
          | M.Text context -> Some (fun (k : (a, (P.drive_result, P.error) result) Effect.Deep.continuation) -> Effect.Deep.continue k (handler.text_value context))
          | M.Act (page, choice, text) -> Some (fun (k : (a, (P.drive_result, P.error) result) Effect.Deep.continuation) -> Effect.Deep.continue k (handler.act page choice ~text))
          | _ -> None) }
