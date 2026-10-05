(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j ^nlintc-7be1 ^nlintc-4gjw. *)
open Ocaml_common
open Typedtree

let base = Tast_iterator.default_iterator

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

let catch_all ~caps emit =
  let rebindings = Path.Tbl.create 8 in
  let raises =
    Paths.values ~caps
      [
        ("Stdlib", [ "raise" ]);
        ("Stdlib", [ "raise_notrace" ]);
        ("Printexc", [ "raise_with_backtrace" ]);
        ("Stdlib", [ "Printexc"; "raise_with_backtrace" ]);
      ]
  in
  let cancelled =
    try
      let initial = Lazy.force Env.initial in
      let description, _ =
        Env.lookup_constructor ~use:false ~loc:Location.none Env.Pattern
          (Paths.lid ("Eio", [ "Cancel"; "Cancelled" ]))
          initial
      in
      match description.Data_types.cstr_tag with
      | Types.Extension path -> Some (Env.normalize_value_path None initial path)
      | _ -> None
    with Not_found | Env.Error _ -> None
  in
  let rec origin en seen path =
    if List.exists (Path.same path) seen then path
    else
      match Path.Tbl.find_opt rebindings path with
      | Some target -> origin en (path :: seen) target
      | None -> Env.normalize_value_path None (Paths.env ~caps en) path
  in
  let rec is_cancelled (p : pattern) =
    match p.pat_desc with
    | Tpat_alias { pattern; _ } -> is_cancelled pattern
    | Tpat_construct (_, description, _, _, _) -> (
        match (description.cstr_tag, cancelled) with
        | Types.Extension path, Some target -> Path.same (origin p.pat_env [] path) target
        | _ -> false)
    | _ -> false
  in
  let binding (p : pattern) =
    match p.pat_desc with
    | Tpat_var { id; _ } | Tpat_alias { id; _ } -> Some id
    | _ -> None
  in
  let raises_binding id e =
    match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) when Paths.is_value ~caps raises fn -> (
        match arguments args with
        | (_, { exp_desc = Texp_ident { path = Path.Pident actual; _ }; _ }) :: _ ->
            Ident.same actual id
        | _ -> false)
    | _ -> false
  in
  (* ^nlintc-du4v: local stamps are unit-relative; exports resolve through the
     compiler environment. Only checked sibling implementations provide evidence. *)
  let definitions = Hashtbl.create 64 and exports = Hashtbl.create 64 in
  let unit_name = ref "" and nesting = ref 0 in
  let local unit id = unit ^ "#" ^ Ident.unique_name id in
  let rec named unit = function
    | Path.Pident id when not (Ident.is_global_or_predef id) -> local unit id
    | Path.Pdot (parent, name) -> named unit parent ^ "." ^ name
    | path -> Path.name path
  in
  let key unit e path =
    named unit (Env.normalize_value_path None (Paths.env ~caps e.exp_env) path)
  in
  let collect unit tree =
    let modules = ref [] and module_identity = ref None in
    let declare ~export vb =
      List.iter
        (fun id ->
          let name = local unit id in
          Hashtbl.replace definitions name (unit, vb.vb_expr);
          if export then begin
            Hashtbl.replace exports
              (String.concat "." ((unit :: !modules) @ [ Ident.name id ]))
              name;
            Option.iter
              (fun parent -> Hashtbl.replace exports (parent ^ "." ^ Ident.name id) name)
              !module_identity
          end)
        (Typedtree.pat_bound_idents vb.vb_pat)
    in
    let iterator =
      {
        base with
        module_binding =
          (fun self binding ->
            let saved, saved_identity = (!modules, !module_identity) in
            let name = Option.value binding.mb_name.txt ~default:"_" in
            modules := !modules @ [ name ];
            module_identity :=
              Some
                (match (!module_identity, binding.mb_id) with
                | None, Some id -> local unit id
                | Some parent, _ -> parent ^ "." ^ name
                | _ -> unit ^ "." ^ name);
            base.module_binding self binding;
            modules := saved;
            module_identity := saved_identity);
        structure_item =
          (fun self item ->
            (match item.str_desc with
            | Tstr_value (_, bindings) -> List.iter (declare ~export:true) bindings
            | _ -> ());
            base.structure_item self item);
        value_binding =
          (fun self vb ->
            declare ~export:false vb;
            base.value_binding self vb);
      }
    in
    iterator.structure iterator tree
  in
  let load tree =
    Hashtbl.clear definitions;
    Hashtbl.clear exports;
    match Artifact.current () with
    | None -> collect !unit_name tree
    | Some artifact ->
        unit_name := Compilation_unit.name_as_string artifact.info.cmt_modname;
        let directory = Filename.dirname artifact.path in
        Array.iter
          (fun name ->
            if Filename.check_suffix name ".cmt" then
              try
                let sibling = Artifact.read ~caps (Filename.concat directory name) in
                if Filename.check_suffix (Artifact.source sibling) ".ml" then begin
                  Artifact.check ~caps
                    ~source:(Artifact.authored_source ~caps sibling)
                    sibling;
                  Artifact.setup ~caps sibling;
                  match sibling.info.cmt_annots with
                  | Implementation tree ->
                      collect
                        (Compilation_unit.name_as_string sibling.info.cmt_modname)
                        tree
                  | _ -> ()
                end
              with Failure _ | Sys_error _ | Unix.Unix_error _ | Env.Error _ -> ())
          (Sys.readdir directory);
        Artifact.setup ~caps artifact;
        collect !unit_name tree
  in
  let rec helper seen unit fn =
    match fn.exp_desc with
    | Texp_function _ -> Some (unit, fn)
    | Texp_ident { path; _ } ->
        let name = key unit fn path in
        let name = Option.value (Hashtbl.find_opt exports name) ~default:name in
        if List.mem name seen then None
        else
          Option.bind (Hashtbl.find_opt definitions name) (fun (unit, body) ->
              helper (name :: seen) unit body)
    | _ -> None
  in
  let same id e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident actual; _ } -> Ident.same actual id
    | _ -> false
  in
  (* Cleanup and helper delegation are legitimate. As with the direct rule,
     prove a reachable re-raise of the original value, not every possible path. *)
  let rec raises_in active unit id e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            if raises_binding id e then found := true;
            match e.exp_desc with
            | Texp_function _ -> ()
            | Texp_apply (fn, args, _, _, _) ->
                let actuals =
                  List.map (function _, Arg (e, _) -> Some e | _ -> None) args
                in
                (match helper [] unit fn with
                | Some
                    ( callee_unit,
                      ({ exp_desc = Texp_function { params; body; _ }; _ } as closure) )
                  when not (List.exists (( == ) closure) active) -> (
                    let active = closure :: active in
                    List.iteri
                      (fun i param ->
                        match List.nth_opt actuals i with
                        | Some (Some arg) when same id arg ->
                            let pattern =
                              match param.fp_kind with
                              | Tparam_pat p | Tparam_optional_default (p, _, _) -> p
                            in
                            let ids =
                              param.fp_param :: Option.to_list (binding pattern)
                            in
                            let bodies =
                              match body with
                              | Tfunction_body e -> [ e ]
                              | Tfunction_cases cases ->
                                  List.map (fun c -> c.c_rhs) cases.fc_cases
                            in
                            if
                              List.exists
                                (fun id ->
                                  List.exists (raises_in active callee_unit id) bodies)
                                ids
                            then found := true
                        | _ -> ())
                      params;
                    match (body, List.nth_opt actuals (List.length params)) with
                    | Tfunction_cases cases, Some (Some arg) when same id arg ->
                        List.iter
                          (fun case ->
                            let ids =
                              cases.fc_param :: Option.to_list (binding case.c_lhs)
                            in
                            if
                              List.exists
                                (fun id -> raises_in active callee_unit id case.c_rhs)
                                ids
                            then found := true)
                          cases.fc_cases
                    | _ -> ())
                | _ -> ());
                base.expr self e
            | Texp_let (_, bindings, body) ->
                List.iter
                  (fun vb ->
                    if same id vb.vb_expr then
                      Option.iter
                        (fun alias ->
                          if raises_in active unit alias body then found := true)
                        (binding vb.vb_pat))
                  bindings;
                base.expr self e
            | Texp_match (scrutinee, _, cases, _, _) when same id scrutinee ->
                List.iter
                  (fun case ->
                    Option.iter
                      (fun alias ->
                        if raises_in active unit alias case.c_rhs then found := true)
                      (Option.bind (fst (Typedtree.split_pattern case.c_lhs)) binding))
                  cases;
                base.expr self e
            | _ -> base.expr self e);
      }
    in
    iterator.expr iterator e;
    !found
  in
  (* ^nlintc-du4v: returning the original exception as data is propagation,
     even though following the caller is deliberately out of scope. *)
  let rec carries id e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident actual; _ } -> Ident.same actual id
    | Texp_tuple (fields, _) -> List.exists (fun (_, e) -> carries id e) fields
    | Texp_construct (_, _, _, fields, _) ->
        List.exists (fun (_, e) -> carries id e) fields
    | Texp_variant (_, Some (payload, _)) -> carries id payload
    | Texp_record { fields; _ } ->
        Array.exists
          (function _, _, Overridden (_, e) -> carries id e | _ -> false)
          fields
    | Texp_record_unboxed_product { fields; _ } ->
        Array.exists
          (function _, _, Overridden (_, e) -> carries id e | _ -> false)
          fields
    | Texp_sequence (_, _, last) | Texp_let (_, _, last) -> carries id last
    | Texp_ifthenelse (_, yes, Some no) -> carries id yes || carries id no
    | Texp_match (_, _, cases, _, _) ->
        List.exists (fun case -> carries id case.c_rhs) cases
    | Texp_try (body, cases, _) ->
        carries id body || List.exists (fun case -> carries id case.c_rhs) cases
    | _ -> false
  in
  (* ^nlintc-du4v: a store is reification only when a visible continuation
     returns or scrutinises that cell. Deferred readers and overwritten cells
     do not establish that the exception leaves this handler. *)
  let following = ref [] in
  let assign = Paths.values ~caps [ ("Stdlib", [ ":=" ]) ] in
  let dereference = Paths.values ~caps [ ("Stdlib", [ "!" ]) ] in
  let ignored = Paths.values ~caps [ ("Stdlib", [ "ignore" ]) ] in
  let cell e =
    match e.exp_desc with
    | Texp_ident { path; _ } -> Some (key !unit_name e path)
    | _ -> None
  in
  let write e =
    match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) when Paths.is_value ~caps assign fn -> (
        match arguments args with
        | [ (_, target); (_, value) ] ->
            Option.map (fun target -> ((target, ""), value)) (cell target)
        | _ -> None)
    | Texp_setfield { record; label; newval; _ } ->
        Option.map (fun target -> ((target, label.lbl_name), newval)) (cell record)
    | _ -> None
  in
  let read target e =
    match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) when Paths.is_value ~caps dereference fn -> (
        match arguments args with
        | [ (_, record) ] ->
            Option.map (fun cell -> (cell, "")) (cell record) = Some target
        | _ -> false)
    | Texp_field { record; label; _ } ->
        Option.map (fun cell -> (cell, label.lbl_name)) (cell record) = Some target
    | _ -> false
  in
  let rec tail_reads target e =
    if read target e then true
    else
      match e.exp_desc with
      | Texp_tuple (fields, _) -> List.exists (fun (_, e) -> tail_reads target e) fields
      | Texp_construct (_, _, _, fields, _) ->
          List.exists (fun (_, e) -> tail_reads target e) fields
      | Texp_variant (_, Some (e, _)) -> tail_reads target e
      | Texp_sequence (_, _, last) | Texp_let (_, _, last) -> tail_reads target last
      | Texp_ifthenelse (_, yes, Some no) -> tail_reads target yes || tail_reads target no
      | Texp_match (_, _, cases, _, _) ->
          List.exists (fun c -> tail_reads target c.c_rhs) cases
      | _ -> false
  in
  let uses target expressions =
    let overwritten = ref false
    and observed = ref (List.exists (tail_reads target) expressions) in
    let contains_read e =
      let found = ref false in
      let iterator =
        {
          base with
          expr =
            (fun self e ->
              if read target e then found := true;
              match e.exp_desc with Texp_function _ -> () | _ -> base.expr self e);
        }
      in
      iterator.expr iterator e;
      !found
    in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            (match write e with
            | Some (cell, _) when cell = target -> overwritten := true
            | _ -> ());
            (match e.exp_desc with
            | Texp_apply (fn, args, _, _, _)
              when (not (Paths.is_value ~caps ignored fn))
                   && not (Paths.is_value ~caps dereference fn) ->
                if List.exists (fun (_, arg) -> contains_read arg) (arguments args) then
                  observed := true
            | Texp_assert (condition, _) ->
                if contains_read condition then observed := true
            | Texp_match (scrutinee, _, cases, _, _)
              when List.exists
                     (fun c ->
                       match fst (Typedtree.split_pattern c.c_lhs) with
                       | Some { pat_desc = Tpat_any; _ } | None -> false
                       | _ -> true)
                     cases ->
                if contains_read scrutinee then observed := true
            | _ -> ());
            match e.exp_desc with
            | Texp_function _ -> ()
            | Texp_apply (fn, _, _, _, _) when Paths.is_value ~caps ignored fn -> ()
            | _ -> base.expr self e);
      }
    in
    List.iter (iterator.expr iterator) expressions;
    !observed && not !overwritten
  in
  let stored id e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            (match write e with
            | Some (target, value) when carries id value && uses target !following ->
                found := true
            | _ -> ());
            match e.exp_desc with Texp_function _ -> () | _ -> base.expr self e);
      }
    in
    iterator.expr iterator e;
    !found
  in
  let propagates id e = raises_in [] !unit_name id e || carries id e || stored id e in
  (* ^nlintc-du4v: terminal conversion is a structural fact at the actual entry,
     not a privilege attached to an entire executable or an arbitrary callback. *)
  let module Nodes = Hashtbl.Make (struct
    type t = expression

    let equal = ( == )
    let hash e = Hashtbl.hash e.exp_loc
  end) in
  let terminal = Nodes.create 16 in
  let exits =
    Paths.values ~caps [ ("Stdlib", [ "exit" ]); ("Ox_caps", [ "Cap_stdlib"; "exit" ]) ]
  in
  let doors =
    Paths.values ~caps
      [ ("Ox_app", [ "run_and_exit" ]); ("Ox_app", [ "run_and_exit_with_args" ]) ]
  in
  let rec tails descend e =
    match e.exp_desc with
    | Texp_sequence (_, _, last) | Texp_let (_, _, last) -> descend last
    | Texp_ifthenelse (_, yes, no) ->
        descend yes;
        Option.iter descend no
    | Texp_match (_, _, cases, _, _) -> List.iter (fun c -> descend c.c_rhs) cases
    | Texp_try (body, cases, _) ->
        descend body;
        List.iter (fun c -> descend c.c_rhs) cases
    | _ -> ()
  and status e =
    Nodes.replace terminal e ();
    tails status e
  in
  let rec entry e =
    (match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) when Paths.is_value ~caps exits fn ->
        List.iter (fun (label, e) -> if label = Nolabel then status e) (arguments args)
    | Texp_apply (fn, args, _, _, _) when Paths.is_value ~caps doors fn -> (
        match List.rev (arguments args) with
        | (Nolabel, { exp_desc = Texp_function { body; _ }; _ }) :: _ -> (
            match body with
            | Tfunction_body e -> status e
            | Tfunction_cases cases -> List.iter (fun c -> status c.c_rhs) cases.fc_cases)
        | _ -> ())
    | _ -> ());
    tails entry e
  in
  let mark_entry tree =
    Nodes.clear terminal;
    match Artifact.current () with
    | Some artifact
      when Caps_policy.executable_entry ~caps (Artifact.authored_source ~caps artifact) ->
        List.iter
          (fun item ->
            match item.str_desc with
            | Tstr_eval (e, _, _) -> entry e
            | Tstr_value (_, bindings) ->
                List.iter
                  (fun vb ->
                    if Typedtree.pat_bound_idents vb.vb_pat = [] then entry vb.vb_expr)
                  bindings
            | _ -> ())
          tree.str_items
    | _ -> ()
  in
  (* ^nlintc-du4v: _exit runs no handlers and returns to no caller, even in a
     fork child owned by a library. Every possible handler result must terminate. *)
  let immediate_exits =
    Paths.values ~caps [ ("Unix", [ "_exit" ]); ("Ox_caps", [ "Cap_unix"; "_exit" ]) ]
  in
  let rec immediate_exit e =
    match e.exp_desc with
    | Texp_apply (fn, _, _, _, _) -> Paths.is_value ~caps immediate_exits fn
    | Texp_sequence (_, _, last) | Texp_let (_, _, last) -> immediate_exit last
    | Texp_ifthenelse (_, yes, Some no) -> immediate_exit yes && immediate_exit no
    | Texp_match (_, _, cases, _, _) ->
        cases <> [] && List.for_all (fun c -> immediate_exit c.c_rhs) cases
    | Texp_try (body, cases, _) ->
        immediate_exit body && List.for_all (fun c -> immediate_exit c.c_rhs) cases
    | _ -> false
  in
  let check cases =
    let cancellation_passes = ref false in
    List.iter
      (fun case ->
        let p = case.c_lhs in
        if is_cancelled p then begin
          let passes =
            immediate_exit case.c_rhs
            || Option.fold ~none:false
                 ~some:(fun id -> propagates id case.c_rhs)
                 (binding p)
          in
          if Option.is_some (binding p) && not passes then emit p.pat_loc;
          if case.c_guard = None && passes then cancellation_passes := true
        end
        else if
          (not !cancellation_passes) && case.c_guard = None
          && not (immediate_exit case.c_rhs)
        then
          match p.pat_desc with
          | Tpat_any -> emit p.pat_loc
          | Tpat_var { id; name = { txt = "exn" | "_exn"; _ }; _ }
            when not (propagates id case.c_rhs) ->
              emit p.pat_loc
          | _ -> ())
      cases
  in
  {
    base with
    structure =
      (fun self tree ->
        if !nesting = 0 then (
          load tree;
          mark_entry tree);
        incr nesting;
        base.structure self tree;
        decr nesting);
    extension_constructor =
      (fun self ext ->
        (match ext.ext_kind with
        | Text_rebind (path, _) ->
            Path.Tbl.replace rebindings (Path.Pident ext.ext_id) path
        | _ -> ());
        base.extension_constructor self ext);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_try (_, cases, _) -> if not (Nodes.mem terminal e) then check cases
        | Texp_match (_, _, cases, _, _) ->
            let exceptions =
              List.filter_map
                (fun case ->
                  match case.c_lhs.pat_desc with
                  | Tpat_exception p -> Some { case with c_lhs = p }
                  | _ -> None)
                cases
            in
            if not (Nodes.mem terminal e) then check exceptions
        | _ -> ());
        match e.exp_desc with
        | Texp_sequence (first, _, last) ->
            let saved = !following in
            following := last :: saved;
            self.expr self first;
            following := saved;
            self.expr self last
        | Texp_let (_, bindings, body) ->
            let saved = !following in
            following := body :: saved;
            List.iter (self.value_binding self) bindings;
            following := saved;
            self.expr self body
        | Texp_function _ ->
            let saved = !following in
            following := [];
            base.expr self e;
            following := saved
        | _ -> base.expr self e);
  }

let identifiers predicate emit =
  {
    base with
    expr =
      (fun self e ->
        if predicate e then emit e.exp_loc;
        base.expr self e);
  }

let obj_magic ~caps emit =
  let modules = Paths.modules ~caps [ ("Stdlib", [ "Obj" ]) ] in
  identifiers
    (fun e ->
      match e.exp_desc with
      | Texp_ident { path; _ } ->
          String.starts_with ~prefix:"magic" (Path.last path)
          && Paths.in_module ~caps modules e
      | _ -> false)
    emit

let raw_concurrency ~caps emit =
  let fiber = Paths.modules ~caps [ ("Eio", [ "Fiber" ]) ] in
  let fiber_list = Paths.modules ~caps [ ("Eio", [ "Fiber"; "List" ]) ] in
  let switch = Paths.modules ~caps [ ("Eio", [ "Switch" ]) ] in
  let mutex = Paths.modules ~caps [ ("Eio", [ "Mutex" ]) ] in
  identifiers
    (fun e ->
      match e.exp_desc with
      | Texp_ident { path; _ } ->
          let name = Path.last path in
          Paths.in_module ~caps mutex e
          || Paths.in_module ~caps fiber_list e
          || Paths.in_module ~caps fiber e
             && (String.starts_with ~prefix:"fork" name
                || List.mem name [ "both"; "pair"; "all"; "any"; "first" ])
          || Paths.in_module ~caps switch e
             && (name = "run" || String.starts_with ~prefix:"on_release" name)
      | _ -> false)
    emit

let sleep_names =
  [
    ("Eio", [ "Time"; "sleep" ]);
    ("Eio", [ "Time"; "sleep_until" ]);
    ("Eio", [ "Time"; "Mono"; "sleep" ]);
    ("Eio", [ "Time"; "Mono"; "sleep_until" ]);
    ("Eio", [ "Time"; "Mono"; "sleep_span" ]);
    ("Eio", [ "Time"; "Timeout"; "sleep" ]);
    ("Eio_unix", [ "sleep" ]);
    ("Ox", [ "Concurrent"; "sleep" ]);
  ]

let suspending_names =
  sleep_names
  @ [
      ("Eio", [ "Fiber"; "yield" ]);
      ("Eio", [ "Fiber"; "await_cancel" ]);
      ("Eio", [ "Promise"; "await" ]);
      ("Eio", [ "Promise"; "await_exn" ]);
      ("Eio", [ "Mutex"; "lock" ]);
      ("Eio", [ "Mutex"; "use_rw" ]);
      ("Eio", [ "Mutex"; "use_ro" ]);
      ("Eio", [ "Condition"; "await" ]);
      ("Eio", [ "Condition"; "await_no_mutex" ]);
      ("Eio", [ "Semaphore"; "acquire" ]);
      ("Eio", [ "Stream"; "add" ]);
      ("Eio", [ "Stream"; "take" ]);
      ("Eio", [ "Flow"; "single_read" ]);
      ("Eio", [ "Flow"; "read_exact" ]);
      ("Eio", [ "Flow"; "write" ]);
      ("Eio", [ "Flow"; "copy" ]);
      ("Eio", [ "Flow"; "copy_string" ]);
      ("Eio", [ "Buf_write"; "flush" ]);
      ("Eio", [ "Process"; "await" ]);
      ("Eio", [ "Process"; "await_exn" ]);
      ("Eio", [ "Process"; "run" ]);
      ("Eio", [ "Net"; "accept" ]);
      ("Eio", [ "Net"; "connect" ]);
      ("Eio", [ "Net"; "send" ]);
      ("Eio", [ "Net"; "recv" ]);
      ("Eio_unix", [ "await_readable" ]);
      ("Eio_unix", [ "await_writable" ]);
      ("Eio_unix", [ "run_in_systhread" ]);
      ("Ox", [ "Channel"; "send" ]);
      ("Ox", [ "Channel"; "receive" ]);
      ("Ox", [ "Select"; "select" ]);
      ("Ox", [ "Fiber"; "await" ]);
      ("Ox", [ "Scope"; "run" ]);
    ]

(* A lock is dangerous only while a scheduler suspension can happen. *)
let stdlib_lock ~caps emit =
  let acquire =
    Paths.values ~caps
      [
        ("Mutex", [ "lock" ]);
        ("Stdlib", [ "Mutex"; "lock" ]);
        ("Semaphore", [ "Counting"; "acquire" ]);
        ("Semaphore", [ "Binary"; "acquire" ]);
      ]
  in
  let release =
    Paths.values ~caps
      [
        ("Mutex", [ "unlock" ]);
        ("Stdlib", [ "Mutex"; "unlock" ]);
        ("Semaphore", [ "Counting"; "release" ]);
        ("Semaphore", [ "Binary"; "release" ]);
      ]
  in
  let suspend = Paths.values ~caps suspending_names in
  let protect =
    Paths.values ~caps [ ("Fun", [ "protect" ]); ("Stdlib", [ "Fun"; "protect" ]) ]
  in
  let immediate = Paths.values ~caps [ ("Eio", [ "Cancel"; "protect" ]) ] in
  (* ^nlintc-j03j: memoise execution states, not just closure identities. The
     outgoing lock set is a transfer result and must be replayed on a cache hit. *)
  let module Nodes = Hashtbl.Make (struct
    type t = expression

    let equal = ( == )
    let hash e = Hashtbl.hash e.exp_loc
  end) in
  let nodes = Nodes.create 64 and next_node = ref 0 in
  let node e =
    match Nodes.find_opt nodes e with
    | Some id -> id
    | None ->
        incr next_node;
        Nodes.add nodes e !next_node;
        !next_node
  in
  let held = ref [] and aliases = ref [] and active = ref [] in
  let closures = Path.Tbl.create 64 and visited = Hashtbl.create 64 in
  let reported = Hashtbl.create 8 in
  let report loc =
    let key = (loc.Location.loc_start.Lexing.pos_fname, loc.loc_start.pos_cnum) in
    if not (Hashtbl.mem reported key) then (
      Hashtbl.add reported key ();
      emit loc)
  in
  let rec key e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } ->
        Some
          (Option.value
             (List.find_map
                (fun (other, name) -> if Ident.same id other then Some name else None)
                !aliases)
             ~default:(Ident.unique_name id))
    | Texp_ident { path; _ } -> Some (Path.name path)
    | Texp_field { record; label; _ } ->
        Option.map (fun name -> name ^ "." ^ label.lbl_name) (key record)
    | _ -> None
  in
  let remember binding =
    match binding.vb_pat.pat_desc with
    | Tpat_var { id; _ } -> (
        (match key binding.vb_expr with
        | Some name -> aliases := (id, name) :: !aliases
        | None -> ());
        match binding.vb_expr.exp_desc with
        | Texp_function _ -> Path.Tbl.replace closures (Path.Pident id) binding.vb_expr
        | _ -> ())
    | _ -> ()
  in
  let union a b = List.sort_uniq String.compare (a @ b) in
  let invoke (self : Tast_iterator.iterator) fn args =
    (* Definitions are checked once in their own context. An invocation without
       incoming locks adds no lock-holding evidence and must not expand its call tree. *)
    let closure =
      if !held = [] then None
      else
        match fn.exp_desc with
        | Texp_function _ -> Some fn
        | Texp_ident { path = Path.Pident _ as path; _ } ->
            Path.Tbl.find_opt closures path
        | _ -> None
    in
    match closure with
    | Some closure when not (List.exists (( == ) closure) !active) ->
        let saved_aliases = !aliases and saved_active = !active in
        active := closure :: !active;
        (match closure.exp_desc with
        | Texp_function { params; body; _ } -> (
            List.iter
              (fun param ->
                match List.assoc_opt param.fp_arg_label args with
                | Some arg -> (
                    match key arg with
                    | Some name ->
                        let pattern =
                          match param.fp_kind with
                          | Tparam_pat p | Tparam_optional_default (p, _, _) -> p
                        in
                        List.iter
                          (fun id -> aliases := (id, name) :: !aliases)
                          (param.fp_param :: Typedtree.pat_bound_idents pattern)
                    | None -> ())
                | None -> ())
              params;
            let substitutions = Hashtbl.create 16 in
            List.iter
              (fun (id, name) ->
                let id = Ident.unique_name id in
                if not (Hashtbl.mem substitutions id) then
                  Hashtbl.add substitutions id name)
              !aliases;
            let substitutions =
              Hashtbl.fold (fun id name acc -> (id, name) :: acc) substitutions []
              |> List.sort compare
            in
            let state = (node closure, !held, substitutions) in
            match Hashtbl.find_opt visited state with
            | Some outgoing -> held := outgoing
            | None ->
                (match body with
                | Tfunction_body body -> self.expr self body
                | Tfunction_cases cases ->
                    let incoming = !held in
                    let outgoing =
                      List.fold_left
                        (fun acc case ->
                          held := incoming;
                          Option.iter (self.expr self) case.c_guard;
                          self.expr self case.c_rhs;
                          union acc !held)
                        [] cases.fc_cases
                    in
                    held := outgoing);
                Hashtbl.add visited state !held)
        | _ -> ());
        aliases := saved_aliases;
        active := saved_active
    | _ -> ()
  in
  {
    base with
    value_binding =
      (fun self binding ->
        remember binding;
        base.value_binding self binding);
    expr =
      (fun self e ->
        match e.exp_desc with
        | Texp_function _ ->
            (* Creating a closure does not execute it under its creator's locks. *)
            let saved_held = !held and saved_aliases = !aliases in
            held := [];
            base.expr self e;
            held := saved_held;
            aliases := saved_aliases
        | Texp_let (_, bindings, _) ->
            let saved = !aliases in
            List.iter remember bindings;
            base.expr self e;
            aliases := saved
        | Texp_ifthenelse (test, yes, no) ->
            self.expr self test;
            let incoming = !held in
            self.expr self yes;
            let after_yes = !held in
            held := incoming;
            Option.iter (self.expr self) no;
            held := union after_yes !held
        | Texp_match (source, _, cases, _, _) ->
            self.expr self source;
            let incoming = !held in
            held :=
              List.fold_left
                (fun acc case ->
                  held := incoming;
                  Option.iter (self.expr self) case.c_guard;
                  self.expr self case.c_rhs;
                  union acc !held)
                [] cases
        | Texp_apply (fn, raw_args, _, _, _) ->
            let args = arguments raw_args in
            List.iter
              (fun (_, arg) ->
                match arg.exp_desc with Texp_function _ -> () | _ -> self.expr self arg)
              args;
            if Paths.is_value ~caps protect fn then begin
              List.iter
                (fun (label, arg) -> if label = Nolabel then invoke self arg [])
                args;
              List.iter
                (fun (label, arg) ->
                  if label = Labelled "finally" then invoke self arg [])
                args
            end
            else if Paths.is_value ~caps immediate fn then
              List.iter
                (fun (label, arg) -> if label = Nolabel then invoke self arg [])
                args
            else begin
              if Paths.is_value ~caps suspend fn && !held <> [] then report e.exp_loc;
              let lock_key = match args with (_, arg) :: _ -> key arg | [] -> None in
              (match lock_key with
              | Some name when Paths.is_value ~caps acquire fn ->
                  held := union [ name ] !held
              | Some name when Paths.is_value ~caps release fn ->
                  held := List.filter (( <> ) name) !held
              | _ -> ());
              invoke self fn args
            end
        | _ -> base.expr self e);
  }

let suspending_finalizer ~caps emit =
  let suspend = Paths.values ~caps suspending_names in
  let finally = Paths.values ~caps [ ("Stdlib", [ "Fun"; "protect" ]) ] in
  let protect = Paths.values ~caps [ ("Eio", [ "Cancel"; "protect" ]) ] in
  let releases =
    Paths.values ~caps
      [
        ("Eio", [ "Switch"; "on_release" ]);
        ("Eio", [ "Switch"; "on_release_cancellable" ]);
      ]
  in
  let cleanup = ref false and protected = ref false in
  let scoped final protection f =
    let old = (!cleanup, !protected) in
    cleanup := final;
    protected := protection;
    Fun.protect
      ~finally:(fun () ->
        let a, b = old in
        cleanup := a;
        protected := b)
      f
  in
  {
    base with
    expr =
      (fun self e ->
        match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) ->
            if !cleanup && (not !protected) && Paths.is_value ~caps suspend fn then
              emit e.exp_loc;
            let is_finally = Paths.is_value ~caps finally fn in
            let is_protect =
              Paths.is_value ~caps protect fn || Paths.is_value ~caps releases fn
            in
            if is_finally || is_protect then begin
              self.expr self fn;
              List.iter
                (fun (label, arg) ->
                  match arg.exp_desc with
                  | Texp_function _
                    when (is_finally && label = Labelled "finally")
                         || (is_protect && label = Nolabel) ->
                      scoped true (is_protect || !protected) (fun () ->
                          self.expr self arg)
                  | _ -> self.expr self arg)
                (arguments args)
            end
            else base.expr self e
        | _ -> base.expr self e);
  }

let race_deadline ~caps emit =
  let races =
    Paths.values ~caps
      [
        ("Ox", [ "Concurrent"; "race" ]);
        ("Ox", [ "Concurrent"; "race_first" ]);
        ("Eio", [ "Fiber"; "any" ]);
      ]
  in
  let sleeps = Paths.values ~caps sleep_names in
  let contains_sleep e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            (match e.exp_desc with
            | Texp_apply (fn, _, _, _, _) when Paths.is_value ~caps sleeps fn ->
                found := true
            | _ -> ());
            base.expr self e);
      }
    in
    iterator.expr iterator e;
    !found
  in
  {
    base with
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _)
          when Paths.is_value ~caps races fn
               && List.exists (fun (_, arg) -> contains_sleep arg) (arguments args) ->
            emit e.exp_loc
        | _ -> ());
        base.expr self e);
  }
