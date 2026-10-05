(* ^safe-eeso ^safe-doj9 ^safe-2led *)
open Ocaml_common
open Typedtree

let check ~caps emit =
  let targets =
    List.map
      (fun name ->
        match Paths.value ~caps ("Stdlib", [ name ]) with
        | Some path -> path
        | None -> failwith ("missing Stdlib comparison identity: " ^ name))
      [ "="; "<>"; "<"; ">"; "<="; ">="; "compare" ]
  in
  let is_function expression =
    match
      Types.get_desc
        (Ctype.expand_head (Paths.env ~caps expression.exp_env) expression.exp_type)
    with
    | Tarrow _ -> true
    | _ -> false
  in
  (* Ident stamps distinguish shadowing. Only simple immutable value bindings in this
     annotation are followed; no wrappers, cross-unit exports or heap data flow. *)
  let bindings = Path.Tbl.create 32 in
  let rec remember_pattern (pattern : pattern) expression =
    match pattern.pat_desc with
    | Tpat_var { id; _ } -> Path.Tbl.replace bindings (Path.Pident id) expression
    | Tpat_alias { id; pattern; _ } ->
        Path.Tbl.replace bindings (Path.Pident id) expression;
        remember_pattern pattern expression
    | _ -> ()
  in
  let remember binding = remember_pattern binding.vb_pat binding.vb_expr in
  let rec operands seen expression =
    if Paths.is_value ~caps targets expression then Some []
    else
      match expression.exp_desc with
      | Texp_ident { path = Path.Pident _ as path; _ }
        when not (List.exists (Path.same path) seen) ->
          Option.bind (Path.Tbl.find_opt bindings path) (operands (path :: seen))
      | Texp_apply (fn, args, _, _, _) ->
          let supplied =
            List.filter_map
              (function Nolabel, Arg (arg, _) -> Some arg | _ -> None)
              args
          in
          if List.length supplied <> List.length args then None
          else
            Option.bind (operands seen fn) (fun previous ->
                let all = previous @ supplied in
                if List.length all <= 2 then Some all else None)
      | Texp_let (_, definitions, body) ->
          List.iter remember definitions;
          operands seen body
      | Texp_open (_, body) -> operands seen body
      | _ -> None
  in
  let base = Tast_iterator.default_iterator in
  {
    base with
    value_binding =
      (fun self binding ->
        remember binding;
        base.value_binding self binding);
    expr =
      (fun self expression ->
        (match expression.exp_desc with
        | Texp_apply _ -> (
            match operands [] expression with
            | Some [ left; right ] when is_function left || is_function right ->
                emit expression.exp_loc
            | _ -> ())
        | _ -> ());
        base.expr self expression);
  }
