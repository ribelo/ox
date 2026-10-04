(* ^nlint-hxar ^nlint-emql: the first typed rule, from the measured spike. *)
open Ocaml_common
open Typedtree

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
}

let env = Envaux.env_of_only_summary ~allow_missing_modules:false
let lid names = Option.get (Longident.unflatten names)

let discarded_result emit =
  let initial = Lazy.force Env.initial in
  let result, _ =
    Env.lookup_type ~use:false ~loc:Location.none (lid [ "Stdlib"; "result" ]) initial
  in
  let result = Env.normalize_type_path None initial result in
  let ignore, _, _ =
    Env.lookup_value ~use:false ~loc:Location.none (lid [ "Stdlib"; "ignore" ]) initial
  in
  let ignore = Env.normalize_value_path None initial ignore in
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

let all =
  [
    {
      id = "ox-discarded-result";
      message =
        "discarded result; match Ok/Error, propagate the error, or name an intentional \
         discard with a reason";
      violating = "test/lint/violating/discard.ml";
      clean = "test/lint/clean/discard.ml";
      documentation = "docs/rules/ox-discarded-result.md";
      source = None;
      typed = Some discarded_result;
    };
  ]

let select ids =
  List.iter
    (fun id ->
      if not (List.exists (fun rule -> rule.id = id) all) then
        invalid_arg ("unknown rule " ^ id))
    ids;
  List.filter (fun rule -> ids = [] || List.mem rule.id ids) all

let self_check ~root rules =
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
