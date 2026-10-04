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
        [ "Stdlib"; "raise" ];
        [ "Stdlib"; "raise_notrace" ];
        [ "Printexc"; "raise_with_backtrace" ];
        [ "Stdlib"; "Printexc"; "raise_with_backtrace" ];
      ]
  in
  let cancelled =
    try
      let initial = Lazy.force Env.initial in
      let description, _ =
        Env.lookup_constructor ~use:false ~loc:Location.none Env.Pattern
          (Paths.lid [ "Eio"; "Cancel"; "Cancelled" ])
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
  (* ^nlintc-du4v: cleanup before propagation is legitimate. Prove only the
     presence of an original-value re-raise, not propagation on every path. *)
  let raises_in id e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            if raises_binding id e then found := true;
            base.expr self e);
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
  let propagates id e = raises_in id e || carries id e in
  let check cases =
    let cancellation_passes = ref false in
    List.iter
      (fun case ->
        let p = case.c_lhs in
        if is_cancelled p then begin
          let passes =
            Option.fold ~none:false ~some:(fun id -> propagates id case.c_rhs) (binding p)
          in
          if Option.is_some (binding p) && not passes then emit p.pat_loc;
          if case.c_guard = None && passes then cancellation_passes := true
        end
        else if (not !cancellation_passes) && case.c_guard = None then
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
        | Texp_try (_, cases, _) -> check cases
        | Texp_match (_, _, cases, _, _) ->
            let exceptions =
              List.filter_map
                (fun case ->
                  match case.c_lhs.pat_desc with
                  | Tpat_exception p -> Some { case with c_lhs = p }
                  | _ -> None)
                cases
            in
            check exceptions
        | _ -> ());
        base.expr self e);
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
  let modules = Paths.modules ~caps [ [ "Stdlib"; "Obj" ] ] in
  identifiers
    (fun e ->
      match e.exp_desc with
      | Texp_ident { path; _ } ->
          String.starts_with ~prefix:"magic" (Path.last path)
          && Paths.in_module ~caps modules e
      | _ -> false)
    emit

let raw_concurrency ~caps emit =
  let fiber = Paths.modules ~caps [ [ "Eio"; "Fiber" ] ] in
  let fiber_list = Paths.modules ~caps [ [ "Eio"; "Fiber"; "List" ] ] in
  let switch = Paths.modules ~caps [ [ "Eio"; "Switch" ] ] in
  let mutex = Paths.modules ~caps [ [ "Eio"; "Mutex" ] ] in
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
    [ "Eio"; "Time"; "sleep" ];
    [ "Eio"; "Time"; "sleep_until" ];
    [ "Eio"; "Time"; "Mono"; "sleep" ];
    [ "Eio"; "Time"; "Mono"; "sleep_until" ];
    [ "Eio"; "Time"; "Mono"; "sleep_span" ];
    [ "Eio"; "Time"; "Timeout"; "sleep" ];
    [ "Eio_unix"; "sleep" ];
    [ "Ox"; "Concurrent"; "sleep" ];
  ]

let suspending_names =
  sleep_names
  @ [
      [ "Eio"; "Fiber"; "yield" ];
      [ "Eio"; "Fiber"; "await_cancel" ];
      [ "Eio"; "Promise"; "await" ];
      [ "Eio"; "Promise"; "await_exn" ];
      [ "Eio"; "Mutex"; "lock" ];
      [ "Eio"; "Mutex"; "use_rw" ];
      [ "Eio"; "Mutex"; "use_ro" ];
      [ "Eio"; "Condition"; "await" ];
      [ "Eio"; "Condition"; "await_no_mutex" ];
      [ "Eio"; "Semaphore"; "acquire" ];
      [ "Eio"; "Stream"; "add" ];
      [ "Eio"; "Stream"; "take" ];
      [ "Eio"; "Flow"; "single_read" ];
      [ "Eio"; "Flow"; "read_exact" ];
      [ "Eio"; "Flow"; "write" ];
      [ "Eio"; "Flow"; "copy" ];
      [ "Eio"; "Flow"; "copy_string" ];
      [ "Eio"; "Buf_write"; "flush" ];
      [ "Eio"; "Process"; "await" ];
      [ "Eio"; "Process"; "await_exn" ];
      [ "Eio"; "Process"; "run" ];
      [ "Eio"; "Net"; "accept" ];
      [ "Eio"; "Net"; "connect" ];
      [ "Eio"; "Net"; "send" ];
      [ "Eio"; "Net"; "recv" ];
      [ "Eio_unix"; "await_readable" ];
      [ "Eio_unix"; "await_writable" ];
      [ "Eio_unix"; "run_in_systhread" ];
      [ "Ox"; "Channel"; "send" ];
      [ "Ox"; "Channel"; "receive" ];
      [ "Ox"; "Select"; "select" ];
      [ "Ox"; "Fiber"; "await" ];
      [ "Ox"; "Scope"; "run" ];
    ]

(* A lock is dangerous only while a scheduler suspension can happen. *)
let stdlib_lock ~caps emit =
  let acquire =
    Paths.values ~caps
      [
        [ "Mutex"; "lock" ];
        [ "Stdlib"; "Mutex"; "lock" ];
        [ "Semaphore"; "Counting"; "acquire" ];
        [ "Semaphore"; "Binary"; "acquire" ];
      ]
  in
  let release =
    Paths.values ~caps
      [
        [ "Mutex"; "unlock" ];
        [ "Stdlib"; "Mutex"; "unlock" ];
        [ "Semaphore"; "Counting"; "release" ];
        [ "Semaphore"; "Binary"; "release" ];
      ]
  in
  let suspend = Paths.values ~caps suspending_names in
  let protect =
    Paths.values ~caps [ [ "Fun"; "protect" ]; [ "Stdlib"; "Fun"; "protect" ] ]
  in
  let immediate = Paths.values ~caps [ [ "Eio"; "Cancel"; "protect" ] ] in
  let held = ref [] and aliases = ref [] and closures = ref [] and active = ref [] in
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
        | Texp_function _ -> closures := (id, binding.vb_expr) :: !closures
        | _ -> ())
    | _ -> ()
  in
  let union a b = List.sort_uniq String.compare (a @ b) in
  let invoke (self : Tast_iterator.iterator) fn args =
    let closure =
      match fn.exp_desc with
      | Texp_function _ -> Some fn
      | Texp_ident { path = Path.Pident id; _ } ->
          List.find_map
            (fun (other, body) -> if Ident.same id other then Some body else None)
            !closures
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
            match body with
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
                held := outgoing)
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
  let finally = Paths.values ~caps [ [ "Stdlib"; "Fun"; "protect" ] ] in
  let protect = Paths.values ~caps [ [ "Eio"; "Cancel"; "protect" ] ] in
  let releases =
    Paths.values ~caps
      [ [ "Eio"; "Switch"; "on_release" ]; [ "Eio"; "Switch"; "on_release_cancellable" ] ]
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
        [ "Ox"; "Concurrent"; "race" ];
        [ "Ox"; "Concurrent"; "race_first" ];
        [ "Eio"; "Fiber"; "any" ];
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
