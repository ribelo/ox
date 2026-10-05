(* ^safe-ldtb ^safe-j6t8 ^safe-y047: identities, never lexical pool names. *)
open Ocaml_common
open Typedtree

let base = Tast_iterator.default_iterator

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

type origin =
  | Symbol of Path.t
  | Tx of expression
  | Fresh of expression * expression list
  | Unknown

type binding = Origin of origin | Created of origin | Expr of expression * environment
and environment = (Ident.t * binding) list

let check ~caps ~emit ~undecided =
  let transactions = Paths.values ~caps [ ("Ox_sql", [ "Pool"; "with_transaction" ]) ] in
  let operations =
    Paths.values ~caps
      (List.map
         (fun name -> ("Ox_sql", [ "Pool"; "Raw"; name ]))
         [ "query"; "fold"; "execute"; "execute_script"; "with_connection" ]
      @ List.map
          (fun name -> ("Ox_sql", [ "Pool"; "Typed"; name ]))
          [ "select"; "returning"; "fold_select"; "execute_compiled"; "run_schema" ])
  in
  let connections =
    Paths.values ~caps [ ("Ox_sql", [ "Pool"; "Raw"; "with_connection" ]) ]
  in
  let folds =
    Paths.values ~caps
      [
        ("Ox_sql", [ "Pool"; "Raw"; "fold" ]);
        ("Ox_sql", [ "Pool"; "Typed"; "fold_select" ]);
      ]
  in
  let pure =
    Paths.values ~caps
      [ ("Stdlib", [ "ignore" ]); ("Stdlib", [ "==" ]); ("Stdlib", [ "!=" ]) ]
  in
  let initial = Lazy.force Env.initial in
  let runner_target =
    try
      let path, declaration =
        Env.lookup_type ~use:false ~loc:Location.none
          (Paths.lid ("Ox_sql", [ "Pool"; "runner" ]))
          initial
      in
      Some (Env.normalize_type_path None initial path, declaration.type_uid)
    with Not_found | Env.Error _ -> None
  in
  let is_runner e =
    let en = Paths.env ~caps e.exp_env in
    match (runner_target, Types.get_desc (Ctype.expand_head en e.exp_type)) with
    | Some (runner_path, uid), Tconstr (path, _, _) ->
        Path.same runner_path (Env.normalize_type_path None en path)
        || Types.Uid.equal uid (Env.find_type path en).type_uid
    | _ -> false
  in
  let rec resolve env seen e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } when not (List.exists (Ident.same id) seen)
      -> (
        match List.find_opt (fun (other, _) -> Ident.same id other) env with
        | Some (_, Expr (target, captured)) ->
            resolve (env @ captured) (id :: seen) target
        | _ -> e)
    | _ -> e
  in
  let known env targets e = Paths.is_value ~caps targets (resolve env [] e) in
  let rec identity env seen e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } -> (
        if List.exists (Ident.same id) seen then Unknown
        else
          match List.find_opt (fun (other, _) -> Ident.same id other) env with
          | Some (_, Origin origin) -> origin
          | Some (_, Created _) -> Unknown
          | Some (_, Expr (target, captured)) ->
              identity (env @ captured) (id :: seen) target
          | None -> Symbol (Path.Pident id))
    | Texp_ident { path; _ } ->
        Symbol (Env.normalize_value_path None (Paths.env ~caps e.exp_env) path)
    | _ -> Unknown
  in
  let same a b =
    match (a, b) with
    | Symbol a, Symbol b -> Path.same a b
    | Tx a, Tx b | Fresh (a, _), Fresh (b, _) -> a == b
    | _ -> false
  in
  let rec bind env (pattern : pattern) value =
    match pattern.pat_desc with
    | Tpat_var { id; _ } -> (id, value) :: env
    | Tpat_alias { pattern; id; _ } -> bind ((id, value) :: env) pattern value
    | _ ->
        List.fold_left
          (fun env id -> (id, Origin Unknown) :: env)
          env (pat_bound_idents pattern)
  in
  let creates = Paths.values ~caps [ ("Ox_sql", [ "Pool"; "create" ]) ] in
  let ok =
    let initial = Lazy.force Env.initial in
    fst
      (Env.lookup_constructor ~use:false ~loc:Location.none Env.Pattern
         (Paths.lid ("Stdlib", [ "Ok" ]))
         initial)
  in
  (* Save allocation-time contexts in result bindings, not at the later Ok match.
     Otherwise an outer create result matched inside a callback acquires false freshness. *)
  let rec creation contexts env seen source =
    match source.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } when not (List.exists (Ident.same id) seen)
      -> (
        match List.find_opt (fun (other, _) -> Ident.same id other) env with
        | Some (_, Created origin) -> Some origin
        | Some (_, Expr (target, captured)) ->
            creation contexts (env @ captured) (id :: seen) target
        | _ -> None)
    | Texp_apply (fn, _, _, _, _) when known env creates fn ->
        let entered =
          List.filter_map (function _, Tx site -> Some site | _ -> None) contexts
        in
        Some (Fresh (source, entered))
    | _ -> None
  in
  let expression_binding contexts env source =
    match creation contexts env [] source with
    | Some origin -> Created origin
    | None -> Expr (source, env)
  in
  let result_binding contexts env source pattern =
    match (creation contexts env [] source, pattern.pat_desc) with
    | Some origin, Tpat_construct (_, desc, _, [ (_, payload) ], _)
      when Types.Uid.equal desc.cstr_uid ok.cstr_uid ->
        bind env payload (Origin origin)
    | _ -> env
  in
  let take label args =
    let rec loop prefix = function
      | [] -> (None, args)
      | (other, value) :: rest when other = label ->
          (Some value, List.rev_append prefix rest)
      | arg :: rest -> loop (arg :: prefix) rest
    in
    loop [] args
  in
  let immediate_scalar e =
    match Types.get_desc (Ctype.expand_head (Paths.env ~caps e.exp_env) e.exp_type) with
    | Tconstr (path, [], _) ->
        List.exists (Path.same path)
          [ Predef.path_int; Predef.path_bool; Predef.path_char; Predef.path_unit ]
    | _ -> false
  in
  let related contexts env e =
    (* Only the transmitted value is scalar: do not prune the capture scan
       inside a function argument whose result happens to be scalar. The main
       walk still checks every eagerly evaluated child operation separately. *)
    if immediate_scalar e then false
    else
      let found = ref false in
      let iterator =
        {
          base with
          expr =
            (fun self e ->
              let origin = identity env [] e in
              if
                is_runner e
                || List.exists
                     (fun (pool, tx) -> same origin pool || same origin tx)
                     contexts
              then found := true;
              base.expr self e);
        }
      in
      iterator.expr iterator (resolve env [] e);
      !found
  in
  let inspect contexts env e =
    let runner = identity env [] e in
    if not (List.exists (fun (_, tx) -> same runner tx) contexts) then
      List.iter
        (fun (pool, tx) ->
          if same runner pool then
            emit e.exp_loc
              "operation uses the originating pool; use the callback transaction runner"
          else if
            (not (same runner tx))
            && not
                 (match (runner, pool, tx) with
                 | Fresh (site, _), Fresh (other, _), _ when site != other -> true
                 | Fresh (_, entered), _, Tx transaction ->
                     List.exists (( == ) transaction) entered
                 | _ -> false)
          then
            undecided e.exp_loc
              "cannot establish whether this runner is independent of the originating \
               pool")
        contexts
  in
  let rec walk contexts env active e =
    let visitor = { base with expr = (fun _ child -> walk contexts env active child) } in
    match e.exp_desc with
    | Texp_function _ when contexts <> [] -> ()
    | Texp_let (_, bindings, body) ->
        List.iter (fun binding -> walk contexts env active binding.vb_expr) bindings;
        let env =
          List.fold_left
            (fun env binding ->
              bind env binding.vb_pat (expression_binding contexts env binding.vb_expr))
            env bindings
        in
        walk contexts env active body
    | Texp_match (source, _, cases, effects, _) ->
        walk contexts env active source;
        List.iter
          (fun case ->
            let pattern, _ = split_pattern case.c_lhs in
            let branch =
              match pattern with
              | Some pattern -> result_binding contexts env source pattern
              | None -> env
            in
            Option.iter (walk contexts branch active) case.c_guard;
            walk contexts branch active case.c_rhs)
          cases;
        List.iter
          (fun case ->
            Option.iter (walk contexts env active) case.c_guard;
            walk contexts env active case.c_rhs)
          effects
    | Texp_apply (fn, raw_args, _, _, _) -> (
        let args = arguments raw_args in
        let owned_callback =
          known env transactions fn
          || (contexts <> [] && (known env connections fn || known env folds fn))
        in
        List.iter
          (fun (_, arg) ->
            match arg.exp_desc with
            | Texp_function _ when not owned_callback ->
                (* Discover roots, not invocation: an ordinary callback cannot
                   inherit the caller's transaction lifetime. Known callbacks
                   are visited exactly once by their invocation dispatch below. *)
                walk [] env active arg
            | Texp_function _ -> ()
            | _ -> walk contexts env active arg)
          args;
        if known env transactions fn then
          match List.filter (fun (label, _) -> label = Nolabel) args with
          | [ (_, pool); (_, callback) ] ->
              inspect contexts env pool;
              let tx = Tx e in
              invoke
                ((identity env [] pool, tx) :: contexts)
                env active callback
                [ (Nolabel, Origin tx) ]
          | _ ->
              undecided e.exp_loc
                "transaction callback or originating pool is unavailable"
        else if contexts <> [] && known env operations fn then
          match List.find_opt (fun (label, _) -> label = Nolabel) args with
          | Some (_, runner) -> (
              match
                Types.get_desc (Ctype.expand_head (Paths.env ~caps e.exp_env) e.exp_type)
              with
              | Tarrow _ ->
                  () (* Constructing a partial application does not run its body. *)
              | _ -> (
                  inspect contexts env runner;
                  if known env connections fn then
                    match List.filter (fun (label, _) -> label = Nolabel) args with
                    | [ _; (_, callback) ] ->
                        invoke contexts env active callback [ (Nolabel, Origin Unknown) ]
                    | _ -> undecided e.exp_loc "SQL connection callback is unavailable"
                  else if known env folds fn then
                    match List.assoc_opt (Labelled "f") args with
                    | Some callback ->
                        invoke contexts env active callback
                          [ (Nolabel, Origin Unknown); (Nolabel, Origin Unknown) ]
                    | None -> undecided e.exp_loc "SQL row callback is unavailable"))
          | None -> undecided e.exp_loc "SQL runner argument is unavailable"
        else if contexts <> [] then
          let closure = resolve env [] fn in
          match closure.exp_desc with
          | Texp_function _ ->
              invoke contexts env active fn
                (List.map
                   (fun (label, arg) -> (label, expression_binding contexts env arg))
                   args)
          | _ ->
              if
                (not (known env pure fn))
                && (related contexts env fn
                   || List.exists (fun (_, arg) -> related contexts env arg) args)
              then
                undecided e.exp_loc
                  "opaque helper receives or captures a SQL runner; routing is unverified"
        )
    | _ -> base.expr visitor e
  and invoke contexts env active callback args =
    let closure = resolve env [] callback in
    if List.exists (( == ) closure) active || List.length active >= 16 then (
      if related contexts env callback then
        undecided callback.exp_loc
          "local helper analysis reached its recursion or depth bound")
    else
      match closure.exp_desc with
      | Texp_function { params; _ } when List.length params > List.length args -> ()
      | Texp_function { params; body; _ } -> (
          let env, remaining =
            List.fold_left
              (fun (env, args) param ->
                let value, args = take param.fp_arg_label args in
                match value with
                | None -> (env, args)
                | Some value ->
                    let pattern =
                      match param.fp_kind with
                      | Tparam_pat p | Tparam_optional_default (p, _, _) -> p
                    in
                    (bind ((param.fp_param, value) :: env) pattern value, args))
              (env, args) params
          in
          let active = closure :: active in
          match body with
          | Tfunction_body body -> walk contexts env active body
          | Tfunction_cases cases ->
              let value, _ = take Nolabel remaining in
              let value = Option.value value ~default:(Origin Unknown) in
              List.iter
                (fun case ->
                  let env = bind ((cases.fc_param, value) :: env) case.c_lhs value in
                  Option.iter (walk contexts env active) case.c_guard;
                  walk contexts env active case.c_rhs)
                cases.fc_cases)
      | _ ->
          undecided callback.exp_loc
            "transaction callback is opaque; runner routing is unverified"
  in
  let environment = ref [] in
  {
    base with
    value_binding =
      (fun _ binding ->
        environment :=
          bind !environment binding.vb_pat
            (expression_binding [] !environment binding.vb_expr);
        walk [] !environment [] binding.vb_expr);
  }
