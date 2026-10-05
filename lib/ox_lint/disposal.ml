(* ^safe-1bc7 ^safe-s6km ^safe-xls8: compiler identities own result and bindings. *)
open Ocaml_common
open Typedtree

let discarded_result ~(caps : < Ox_caps.Cap.fs_read ; .. >) emit =
  ignore caps#fs_read;
  let env = Paths.env ~caps in
  let lid = Paths.lid in
  let initial = Lazy.force Env.initial in
  let result, _ =
    Env.lookup_type ~use:false ~loc:Location.none (lid [ "Stdlib"; "result" ]) initial
  in
  let result = Env.normalize_type_path None initial result in
  let is_result en ty =
    let en = env en in
    match Types.get_desc (Ctype.expand_head en ty) with
    | Tconstr (path, [ _; _ ], _) ->
        Path.same (Env.normalize_type_path None en path) result
    | _ -> false
  in
  let standard names =
    match Paths.value ~caps names with
    | Some path -> path
    | None -> failwith "unresolved required standard disposal identity"
  in
  let discarders =
    List.map standard
      [
        [ "Stdlib"; "ignore" ];
        [ "Stdlib"; "Result"; "to_option" ];
        [ "Stdlib"; "Result"; "iter" ];
        [ "Stdlib"; "Result"; "value" ];
      ]
  in
  let aliases = Hashtbl.create 16 in
  let constants = Hashtbl.create 16 in
  let apply = standard [ "Stdlib"; "@@" ] in
  let pipe = standard [ "Stdlib"; "|>" ] in
  let is_value target e = Paths.is_value ~caps [ target ] e in
  let discarder e =
    match e.exp_desc with
    | Texp_ident { path; _ } -> (
        List.exists
          (Path.same (Env.normalize_value_path None (env e.exp_env) path))
          discarders
        ||
        match path with
        | Path.Pident id -> Hashtbl.mem aliases (Ident.unique_name id)
        | _ -> false)
    | _ -> false
  in
  let logging =
    List.map standard
      [
        [ "Stdlib"; "prerr_endline" ];
        [ "Stdlib"; "prerr_string" ];
        [ "Stdlib"; "print_endline" ];
        [ "Stdlib"; "print_string" ];
      ]
  in
  let rec external_name = function
    | Path.Pident id when Ident.is_global_or_predef id -> Some (Ident.name id)
    | Path.Pdot (root, name) ->
        Option.map (fun root -> root ^ "." ^ name) (external_name root)
    | _ -> None
  in
  let log_call e =
    match e.exp_desc with
    | Texp_apply (fn, _, _, _, _) -> (
        List.exists (fun target -> is_value target fn) logging
        ||
        match fn.exp_desc with
        | Texp_ident { path; _ } -> (
            match external_name (Env.normalize_value_path None (env fn.exp_env) path) with
            | Some name ->
                List.mem name
                  [
                    "Logs.err";
                    "Logs.warn";
                    "Logs.info";
                    "Logs.debug";
                    "Logs.app";
                    "Ox_caps.Cap_stdlib.prerr_string";
                    "Ox_caps.Cap_stdlib.prerr_endline";
                    "Ox_caps.Cap_stdlib.eprintf";
                    "Ox_caps__Cap_stdlib.prerr_string";
                    "Ox_caps__Cap_stdlib.prerr_endline";
                    "Ox_caps__Cap_stdlib.eprintf";
                  ]
            | None -> false)
        | _ -> false)
    | _ -> false
  in
  let is_unit e =
    let en = env e.exp_env in
    match Types.get_desc (Ctype.expand_head en e.exp_type) with
    | Tconstr (path, [], _) ->
        Path.same (Env.normalize_type_path None en path) Predef.path_unit
    | _ -> false
  in
  let rec constant e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } ->
        Hashtbl.mem constants (Ident.unique_name id)
    | Texp_constant _ -> true
    | Texp_construct (_, desc, _, args, _) ->
        (not (is_result e.exp_env e.exp_type && desc.Data_types.cstr_name = "Error"))
        && List.for_all (fun (_, arg) -> constant arg) args
    | Texp_variant (_, None) -> true
    | Texp_variant (_, Some (arg, _)) -> constant arg
    | Texp_tuple (args, _) -> List.for_all (fun (_, arg) -> constant arg) args
    | Texp_apply _ when log_call e && is_unit e -> true
    | Texp_sequence (head, _, tail) -> log_call head && constant tail
    | Texp_let (_, bindings, tail) ->
        List.for_all (fun binding -> constant binding.vb_expr) bindings && constant tail
    | _ -> false
  in
  let rec named_error : type k. k general_pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_alias { pattern; _ } -> named_error pattern
    | Tpat_construct _ | Tpat_variant _ | Tpat_constant _ -> true
    | Tpat_or (a, b, _) -> named_error a && named_error b
    | _ -> false
  in
  let rec error_pattern : type k. k general_pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_value v -> error_pattern (v :> pattern)
    | Tpat_construct (_, desc, _, args, _) ->
        is_result p.pat_env p.pat_type
        && desc.Data_types.cstr_name = "Error"
        && not (List.for_all (fun (_, arg) -> named_error arg) args)
    | Tpat_alias { pattern = inner; _ } -> error_pattern inner
    | Tpat_or (a, b, _) -> error_pattern a || error_pattern b
    | _ -> false
  in
  let rec status e =
    match e.exp_desc with
    | Texp_constant (Const_int n) -> Some ("int", string_of_int n)
    | Texp_construct (_, desc, _, [], _)
      when List.mem desc.Data_types.cstr_name [ "true"; "false" ] ->
        Some ("bool", desc.Data_types.cstr_name)
    | Texp_sequence (_, _, tail) | Texp_let (_, _, tail) -> status tail
    | _ -> None
  in
  let assertions =
    List.map standard
      [
        [ "Stdlib"; "failwith" ];
        [ "Stdlib"; "invalid_arg" ];
        [ "Stdlib"; "raise" ];
        [ "Stdlib"; "raise_notrace" ];
      ]
    @ List.filter_map
        (fun name -> Paths.value ~caps [ "Alcotest"; name ])
        [ "fail"; "failf" ]
  in
  let terminal e =
    match e.exp_desc with
    | Texp_apply (fn, _, _, _, _) ->
        List.exists (fun target -> is_value target fn) assertions
    | _ -> false
  in
  let bool = Predef.path_bool in
  let is_bool e =
    let en = env e.exp_env in
    match Types.get_desc (Ctype.expand_head en e.exp_type) with
    | Tconstr (path, [], _) -> Path.same (Env.normalize_type_path None en path) bool
    | _ -> false
  in
  let base = Tast_iterator.default_iterator in
  let used id body =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            (match e.exp_desc with
            | Texp_ident { path = Path.Pident actual; _ } when Ident.same id actual ->
                found := true
            | _ -> ());
            base.expr self e);
      }
    in
    iterator.expr iterator body;
    !found
  in
  (* Only these binders name the same whole value. Do not search tuple/record
     components: using a sibling field cannot retain a wildcard result. *)
  let rec retains_value body pattern =
    match pattern.pat_desc with
    | Tpat_var { id; _ } -> used id body
    | Tpat_alias { id; pattern; _ } -> used id body || retains_value body pattern
    | _ -> false
  in
  let comparisons =
    List.map
      (fun name -> standard [ "Stdlib"; name ])
      [ "="; "<>"; "<"; "<="; ">"; ">="; "=="; "!=" ]
  in
  let observes_error case =
    match case.c_guard with
    | Some { exp_desc = Texp_apply (fn, arguments, _, _, _); _ }
      when List.exists (fun target -> is_value target fn) comparisons ->
        let binders = ref [] in
        let iterator =
          {
            base with
            pat =
              (fun (type k) self (p : k general_pattern) ->
                (match p.pat_desc with
                | Tpat_var { id; _ } | Tpat_alias { id; _ } -> binders := id :: !binders
                | _ -> ());
                base.pat self p);
          }
        in
        iterator.pat iterator case.c_lhs;
        List.exists
          (fun (_, arg) ->
            match arg with
            | Arg (expression, _) -> List.exists (fun id -> used id expression) !binders
            | _ -> false)
          arguments
    | _ -> false
  in
  let rec accepts_error : type k. k general_pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_value v -> accepts_error (v :> pattern)
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> accepts_error pattern
    | Tpat_or (a, b, _) -> accepts_error a || accepts_error b
    | Tpat_construct (_, desc, _, _, _) ->
        is_result p.pat_env p.pat_type && desc.Data_types.cstr_name = "Error"
    | _ -> false
  in
  let recovers_after cases =
    let alternatives = List.filter (fun case -> accepts_error case.c_lhs) cases in
    alternatives <> []
    && List.exists (fun case -> Option.is_none case.c_guard) alternatives
    && List.for_all
         (fun case -> not (constant case.c_rhs || log_call case.c_rhs))
         alternatives
  in
  let check_cases cases =
    let statuses = List.map (fun case -> status case.c_rhs) cases in
    let preserves_status =
      match statuses with
      | Some (kind, first) :: rest ->
          rest <> []
          && List.for_all (function Some (k, _) -> k = kind | None -> false) rest
          && List.exists
               (function Some (_, value) -> value <> first | None -> false)
               rest
      | _ -> false
    in
    let boolean_projection =
      List.for_all (fun case -> is_bool case.c_rhs) cases
      && List.exists Option.is_none statuses
    in
    let expected_error =
      List.exists (fun case -> error_pattern case.c_lhs) cases
      && List.for_all
           (fun case ->
             if error_pattern case.c_lhs then is_unit case.c_rhs && constant case.c_rhs
             else terminal case.c_rhs)
           cases
    in
    if not (preserves_status || boolean_projection || expected_error) then
      let rec check = function
        | [] -> ()
        | case :: remaining ->
            if
              error_pattern case.c_lhs && constant case.c_rhs
              && not (observes_error case && recovers_after remaining)
            then emit case.c_rhs.exp_loc;
            check remaining
      in
      check cases
  in
  let binding_body = ref None in
  let retained = ref [] in
  let rec returned e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } when is_result e.exp_env e.exp_type ->
        [ id ]
    | Texp_sequence (_, _, tail) | Texp_let (_, _, tail) -> returned tail
    | _ -> []
  in
  {
    base with
    expr =
      (fun self e ->
        let saved = !retained in
        let saved_body = !binding_body in
        (binding_body :=
           match e.exp_desc with Texp_let (_, _, body) -> Some body | _ -> None);
        retained := returned e @ saved;
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) when discarder fn ->
            List.iter
              (function
                | _, Arg (arg, _) when is_result arg.exp_env arg.exp_type ->
                    emit arg.exp_loc
                | _ -> ())
              args
        | Texp_apply (fn, [ (_, Arg (a, _)); (_, Arg (b, _)) ], _, _, _)
          when is_value apply fn || is_value pipe fn ->
            let discard, arg = if is_value pipe fn then (b, a) else (a, b) in
            if discarder discard && is_result arg.exp_env arg.exp_type then
              emit arg.exp_loc
        | Texp_sequence (first, _, _) when is_result first.exp_env first.exp_type ->
            emit first.exp_loc
        | Texp_match (subject, _, cases, _, _) ->
            let observed =
              match subject.exp_desc with
              | Texp_ident { path = Path.Pident id; _ } ->
                  List.exists (Ident.same id) !retained
              | _ -> false
            in
            if not observed then check_cases cases
        | Texp_function { body = Tfunction_cases { fc_cases = cases; _ }; _ } ->
            check_cases cases
        | _ -> ());
        base.expr self e;
        retained := saved;
        binding_body := saved_body);
    value_binding =
      (fun self vb ->
        let body = !binding_body in
        binding_body := None;
        let patterns =
          {
            base with
            pat =
              (fun (type k) self (p : k general_pattern) ->
                match p.pat_desc with
                | Tpat_any when is_result p.pat_env p.pat_type -> emit p.pat_loc
                | Tpat_alias { id; pattern; _ } -> (
                    match body with
                    | None -> ()
                    | Some body when used id body || retains_value body pattern -> ()
                    | Some _ when is_result p.pat_env p.pat_type -> emit p.pat_loc
                    | Some _ -> base.pat self p)
                | Tpat_var { id; _ } when is_result p.pat_env p.pat_type -> (
                    match body with
                    | Some body when not (used id body) -> emit p.pat_loc
                    | _ -> ())
                | _ -> base.pat self p);
          }
        in
        patterns.pat patterns vb.vb_pat;
        (match vb.vb_pat.pat_desc with
        | Tpat_var { id; _ } when constant vb.vb_expr ->
            Hashtbl.replace constants (Ident.unique_name id) ()
        | _ -> ());
        (match vb.vb_pat.pat_desc with
        | Tpat_var { id; _ } when discarder vb.vb_expr ->
            Hashtbl.replace aliases (Ident.unique_name id) ()
        | _ -> ());
        base.value_binding self vb;
        binding_body := body);
  }
