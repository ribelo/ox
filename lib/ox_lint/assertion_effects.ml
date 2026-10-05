(* ^safe-pcom ^safe-u7cx: evaluated expressions, not sequence spelling or suspension. *)
open Ocaml_common
open Typedtree

let check ~caps ~emit ~undecided =
  let base = Tast_iterator.default_iterator in
  let bindings = ref [] in
  let collector =
    {
      base with
      value_binding =
        (fun self vb ->
          (match vb.vb_pat.pat_desc with
          | Tpat_var { id; _ } -> bindings := (id, vb.vb_expr) :: !bindings
          | _ -> ());
          base.value_binding self vb);
    }
  in
  let resolve entries =
    List.filter_map
      (fun (((first, rest) as name), arity) ->
        Option.map (fun path -> (path, first :: rest, arity)) (Paths.value ~caps name))
      entries
  in
  let writes =
    resolve
      [
        (("Stdlib", [ "incr" ]), 1);
        (("Stdlib", [ "print_endline" ]), 1);
        (("Stdlib", [ "Array"; "set" ]), 3);
        (("Stdlib", [ ":=" ]), 2);
        (("Stdlib", [ "decr" ]), 1);
        (("Stdlib", [ "Bytes"; "set" ]), 3);
        (("Stdlib", [ "Buffer"; "add_string" ]), 2);
        (("Stdlib", [ "Hashtbl"; "replace" ]), 3);
        (("Stdlib", [ "output_string" ]), 2);
        (("Stdlib", [ "Atomic"; "set" ]), 2);
        (("Stdlib", [ "Atomic"; "exchange" ]), 2);
        (("Stdlib", [ "Atomic"; "fetch_and_add" ]), 2);
      ]
  in
  (* Exact pinned primitives: no user/native callback. Polymorphic comparison needs
     a scalar operand or the typed empty-list proof below, never arbitrary payloads. *)
  let pure =
    resolve
      (List.map
         (fun (name, arity) -> (("Stdlib", [ name ]), arity))
         [
           ("ignore", 1);
           ("not", 1);
           ("ref", 1);
           ("!", 1);
           ("+", 2);
           ("-", 2);
           ("*", 2);
           ("/", 2);
           ("mod", 2);
           ("~-", 1);
           ("~+", 1);
           ("==", 2);
           ("!=", 2);
           ("&&", 2);
           ("||", 2);
         ]
      @ [ (("Stdlib", [ "Atomic"; "get" ]), 1) ])
  in
  let comparisons =
    Paths.values ~caps
      (List.map (fun name -> ("Stdlib", [ name ])) [ "="; "<>"; "<"; ">"; "<="; ">=" ])
  in
  let scalar e =
    match Types.get_desc e.exp_type with
    | Tconstr (path, [], _) ->
        List.exists (Path.same path)
          [
            Predef.path_int;
            Predef.path_bool;
            Predef.path_char;
            Predef.path_string;
            Predef.path_unit;
            Predef.path_float;
          ]
    | _ -> false
  in
  let list_type e =
    match Types.get_desc e.exp_type with
    | Tconstr (path, [ _ ], _) -> Path.same path Predef.path_list
    | _ -> false
  in
  (* The exact built-in list type has one nullary constant constructor: nil.
     Nil versus nil/cons settles at the immediate/block distinction, before any
     closure/custom element payload. Operand evaluation is still walked below. *)
  let empty_list e =
    list_type e
    &&
    match e.exp_desc with
    | Texp_construct (_, desc, _, [], _) -> desc.cstr_constant && desc.cstr_arity = 0
    | _ -> false
  in
  let comparison_without_payloads args =
    match args with
    | [ (_, left); (_, right) ] ->
        scalar left
        || (list_type left && list_type right && (empty_list left || empty_list right))
    | [ (_, first) ] -> scalar first
    | _ -> false
  in
  let supplied args =
    List.filter_map
      (function label, Arg (e, _) -> Some (label, e) | _, Omitted _ -> None)
      args
  in
  let name fn =
    match fn.exp_desc with
    | Texp_ident { path; _ } -> Path.name path
    | Texp_mutvar id -> Ident.name id.txt
    | _ -> "indirect function"
  in
  let unknown loc reason = undecided loc ("unverified assertion call: " ^ reason) in
  let lazy_pattern pattern =
    let found = ref false in
    let patterns =
      {
        base with
        pat =
          (fun (type k) self (p : k general_pattern) ->
            (match p.pat_desc with Tpat_lazy _ -> found := true | _ -> ());
            base.pat self p);
      }
    in
    patterns.pat patterns pattern;
    !found
  in
  let rec evaluated trail origin e =
    let loc = Option.value origin ~default:e.exp_loc in
    let self =
      {
        base with
        expr = (fun _ e -> evaluated trail origin e);
        pat =
          (fun (type k) self (p : k general_pattern) ->
            (match p.pat_desc with
            | Tpat_lazy _ -> unknown loc "lazy pattern forcing"
            | _ -> ());
            base.pat self p);
      }
    in
    match e.exp_desc with
    | Texp_function _ | Texp_lazy _ -> ()
    (* The outer visitor checks every nested assertion once in its own right. *)
    | Texp_assert _ -> ()
    | Texp_setfield _ | Texp_setinstvar _ | Texp_setmutvar _ ->
        emit loc "mutation in assertion condition disappears with -noassert";
        base.expr self e
    | Texp_apply (fn, args, _, _, _) ->
        base.expr self e;
        invoke trail loc (name fn) fn (supplied args)
    | Texp_letop { let_; ands; _ } ->
        unknown loc ("binding operator " ^ Path.name let_.bop_op_path);
        List.iter (fun op -> evaluated trail origin op.bop_exp) (let_ :: ands)
    | Texp_probe { name; _ } -> unknown loc ("probe " ^ name)
    | Texp_overwrite _ -> unknown loc "ownership overwrite"
    | Texp_quotation _ | Texp_antiquotation _ -> unknown loc "staged expression"
    | Texp_send _ | Texp_new _ | Texp_object _ ->
        unknown loc "object dispatch/initialization";
        base.expr self e
    | _ -> base.expr self e
  and invoke trail loc call_name fn args =
    match List.find_opt (fun (path, _, _) -> Paths.is_value ~caps [ path ] fn) writes with
    | Some (_, names, arity) ->
        if List.length args >= arity then
          emit loc
            (String.concat "." names ^ " in assertion condition disappears with -noassert")
    | None when List.exists (fun (path, _, _) -> Paths.is_value ~caps [ path ] fn) pure
      -> (
        match
          List.find_opt (fun (path, _, _) -> Paths.is_value ~caps [ path ] fn) pure
        with
        | Some (_, names, arity) when List.length args > arity ->
            unknown loc ("returned function from " ^ String.concat "." names)
        | _ -> ())
    | None when Paths.is_value ~caps comparisons fn && comparison_without_payloads args ->
        ()
    | None -> (
        match fn.exp_desc with
        | Texp_ident { path = Path.Pident id; _ } -> (
            if List.exists (Ident.same id) trail then
              unknown loc ("recursive helper " ^ name fn)
            else
              match List.find_opt (fun (key, _) -> Ident.same id key) !bindings with
              | Some (_, body) -> invoke (id :: trail) loc call_name body args
              | None -> unknown loc (name fn))
        | Texp_apply (partial, prior, _, _, _) ->
            invoke trail loc call_name partial (supplied prior @ args)
        | Texp_function { params; body; _ } ->
            let arity =
              List.length params
              + match body with Tfunction_body _ -> 0 | Tfunction_cases _ -> 1
            in
            if List.length args >= arity then
              if
                List.exists
                  (fun p ->
                    match p.fp_kind with
                    | Tparam_optional_default _ -> true
                    | Tparam_pat p -> lazy_pattern p)
                  params
                ||
                match body with
                | Tfunction_cases cases ->
                    List.exists (fun c -> lazy_pattern c.c_lhs) cases.fc_cases
                | Tfunction_body _ -> false
              then unknown loc ("optional or lazy parameter of " ^ call_name)
              else (
                (match body with
                | Tfunction_body e -> evaluated trail (Some loc) e
                | Tfunction_cases cases ->
                    List.iter
                      (fun c ->
                        Option.iter (evaluated trail (Some loc)) c.c_guard;
                        evaluated trail (Some loc) c.c_rhs)
                      cases.fc_cases);
                if List.length args > arity then
                  unknown loc ("returned function from local helper " ^ call_name))
        | _ -> unknown loc (name fn))
  in
  {
    base with
    structure =
      (fun self tree ->
        collector.structure collector tree;
        base.structure self tree);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_assert (condition, _) -> evaluated [] None condition
        | _ -> ());
        base.expr self e);
  }
