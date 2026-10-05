(* ^safe-prune: restore the 2026-10-04 ignore/wildcard detector. *)
open Ocaml_common
open Typedtree

let discarded_result ~(caps : < Ox_caps.Cap.fs_read ; .. >) emit =
  ignore caps#fs_read;
  let env = Paths.env ~caps in
  let lid = Paths.lid in
  let initial = Lazy.force Env.initial in
  let result, _ =
    Env.lookup_type ~use:false ~loc:Location.none (lid ("Stdlib", [ "result" ])) initial
  in
  let result = Env.normalize_type_path None initial result in
  let ignore =
    match Paths.value ~caps ("Stdlib", [ "ignore" ]) with
    | Some path -> path
    | None -> failwith "unresolved required standard disposal identity"
  in
  let report loc e =
    let en = env e.exp_env in
    match Types.get_desc (Ctype.expand_head en e.exp_type) with
    | Tconstr (path, [ _; _ ], _)
      when Path.same (Env.normalize_type_path None en path) result ->
        emit loc
    | _ -> ()
  in
  let base = Tast_iterator.default_iterator in
  {
    base with
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) -> (
            match fn.exp_desc with
            | Texp_ident { path; _ }
              when Path.same (Env.normalize_value_path None (env fn.exp_env) path) ignore
              ->
                List.iter
                  (function _, Arg (arg, _) -> report e.exp_loc arg | _ -> ())
                  args
            | _ -> ())
        | _ -> ());
        base.expr self e);
    value_binding =
      (fun self vb ->
        (match vb.vb_pat.pat_desc with
        | Tpat_any -> report vb.vb_pat.pat_loc vb.vb_expr
        | _ -> ());
        base.value_binding self vb);
  }
