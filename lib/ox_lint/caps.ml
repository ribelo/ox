(* ^ncapslint-nf4t ^ncapslint-8jcy: compiler-resolved dangerous origins. *)
open Ocaml_common
open Typedtree

type operation = { name : string; calls : string list list }

let operations =
  [
    { name = "fork"; calls = [ [ "Unix"; "fork" ] ] };
    {
      name = "exec";
      calls =
        [
          [ "Unix"; "execv" ];
          [ "Unix"; "execve" ];
          [ "Unix"; "execvp" ];
          [ "Unix"; "execvpe" ];
          [ "Unix"; "create_process" ];
          [ "Unix"; "create_process_env" ];
          [ "Unix"; "open_process_in" ];
          [ "Unix"; "open_process_out" ];
          [ "Unix"; "open_process" ];
          [ "Unix"; "open_process_full" ];
          [ "Unix"; "open_process_args_in" ];
          [ "Unix"; "open_process_args_out" ];
          [ "Unix"; "open_process_args" ];
          [ "Unix"; "open_process_args_full" ];
          [ "Unix"; "system" ];
          [ "Sys"; "command" ];
        ];
    };
    { name = "exit"; calls = [ [ "Stdlib"; "exit" ]; [ "Unix"; "_exit" ] ] };
    {
      name = "chdir";
      calls = [ [ "Sys"; "chdir" ]; [ "Unix"; "chdir" ]; [ "Unix"; "chroot" ] ];
    };
    {
      name = "env";
      calls =
        [
          [ "Sys"; "getenv" ];
          [ "Sys"; "getenv_opt" ];
          [ "Unix"; "getenv" ];
          [ "Unix"; "environment" ];
          [ "Unix"; "unsafe_environment" ];
          [ "Unix"; "putenv" ];
        ];
    };
    {
      name = "signal";
      calls =
        [
          [ "Unix"; "kill" ];
          [ "Unix"; "sigprocmask" ];
          [ "Sys"; "signal" ];
          [ "Sys"; "set_signal" ];
        ];
    };
    {
      name = "time";
      calls = [ [ "Unix"; "time" ]; [ "Unix"; "gettimeofday" ]; [ "Sys"; "time" ] ];
    };
    {
      name = "random";
      calls = [ [ "Random"; "self_init" ]; [ "Random"; "State"; "make_self_init" ] ];
    };
    {
      name = "stdin";
      calls =
        [
          [ "Stdlib"; "stdin" ];
          [ "In_channel"; "stdin" ];
          [ "Stdlib"; "read_line" ];
          [ "Stdlib"; "read_int" ];
          [ "Stdlib"; "read_int_opt" ];
          [ "Scanf"; "scanf" ];
        ];
    };
    {
      name = "stdout";
      calls =
        [
          [ "Stdlib"; "print_string" ];
          [ "Stdlib"; "print_bytes" ];
          [ "Stdlib"; "print_char" ];
          [ "Stdlib"; "print_int" ];
          [ "Stdlib"; "print_float" ];
          [ "Stdlib"; "print_endline" ];
          [ "Stdlib"; "print_newline" ];
          [ "Stdlib"; "stdout" ];
          [ "Out_channel"; "stdout" ];
          [ "Printf"; "printf" ];
          [ "Format"; "printf" ];
          [ "Format"; "std_formatter" ];
        ];
    };
    {
      name = "stderr";
      calls =
        [
          [ "Stdlib"; "prerr_string" ];
          [ "Stdlib"; "prerr_bytes" ];
          [ "Stdlib"; "prerr_char" ];
          [ "Stdlib"; "prerr_int" ];
          [ "Stdlib"; "prerr_float" ];
          [ "Stdlib"; "prerr_endline" ];
          [ "Stdlib"; "prerr_newline" ];
          [ "Stdlib"; "stderr" ];
          [ "Out_channel"; "stderr" ];
          [ "Printf"; "eprintf" ];
          [ "Format"; "eprintf" ];
          [ "Format"; "err_formatter" ];
        ];
    };
    {
      name = "fs-read";
      calls =
        [
          [ "Stdlib"; "open_in" ];
          [ "Stdlib"; "open_in_bin" ];
          [ "Stdlib"; "open_in_gen" ];
          [ "In_channel"; "open_bin" ];
          [ "In_channel"; "open_text" ];
          [ "In_channel"; "open_gen" ];
          [ "In_channel"; "with_open_bin" ];
          [ "In_channel"; "with_open_text" ];
          [ "In_channel"; "with_open_gen" ];
          [ "Sys"; "readdir" ];
          [ "Unix"; "opendir" ];
        ];
    };
    {
      name = "fs-write";
      calls =
        [
          [ "Stdlib"; "open_out" ];
          [ "Stdlib"; "open_out_bin" ];
          [ "Stdlib"; "open_out_gen" ];
          [ "Out_channel"; "open_bin" ];
          [ "Out_channel"; "open_text" ];
          [ "Out_channel"; "open_gen" ];
          [ "Out_channel"; "with_open_bin" ];
          [ "Out_channel"; "with_open_text" ];
          [ "Out_channel"; "with_open_gen" ];
          [ "Unix"; "openfile" ];
          [ "Sys"; "remove" ];
          [ "Sys"; "rename" ];
          [ "Sys"; "mkdir" ];
          [ "Sys"; "rmdir" ];
          [ "Unix"; "unlink" ];
          [ "Unix"; "rename" ];
          [ "Unix"; "mkdir" ];
          [ "Unix"; "rmdir" ];
          [ "Unix"; "chmod" ];
          [ "Unix"; "truncate" ];
          [ "Unix"; "symlink" ];
          [ "Unix"; "link" ];
        ];
    };
    {
      name = "tmp";
      calls =
        [
          [ "Filename"; "temp_file" ];
          [ "Filename"; "open_temp_file" ];
          [ "Filename"; "temp_dir" ];
        ];
    };
    {
      name = "network";
      calls =
        [
          [ "Unix"; "socket" ];
          [ "Unix"; "socketpair" ];
          [ "Unix"; "open_connection" ];
          [ "Unix"; "establish_server" ];
        ];
    };
    {
      name = "mint";
      calls =
        [
          [ "Ox_caps_door"; "powerbox" ];
          [ "Ox_caps"; "Cap"; "powerbox" ];
          [ "Cap"; "powerbox" ];
          [ "Ox_test"; "powerbox" ];
          [ "Ox_app"; "with_powerbox" ];
        ];
    };
    { name = "forge"; calls = [ [ "Obj"; "magic" ] ] };
  ]

let resolved_calls calls =
  List.concat_map
    (fun names ->
      names
      ::
      (match names with
      | ( "Sys" | "Random" | "Scanf" | "Printf" | "Format" | "In_channel" | "Out_channel"
        | "Filename" | "Obj" )
        :: _ ->
          [ "Stdlib" :: names ]
      | _ -> []))
    calls

let door_boundary ~caps loc =
  Caps_policy.declares_door ~caps loc.Location.loc_start.Lexing.pos_fname

let arguments args = List.filter_map (function _, Arg (e, _) -> Some e | _ -> None) args

(* ^ncapslint-nf4t ^ncapslint-87ld: mandatory compiler-parser source tier.
   The source symbol table resolves opens, module aliases and local binders;
   opaque external re-exports are a typed-tier responsibility. *)
let source ~caps name emit context (base : Ast_iterator.iterator) =
  let potential_authority = ref false in
  let op = List.find (fun op -> op.name = name) operations in
  let targets = List.map (String.concat ".") op.calls in
  let door id loc =
    if name = "mint" && not (door_boundary ~caps loc) then
      match Syntax.module_origin context id with
      | Some path
        when path = "Ox_caps_door" || String.starts_with ~prefix:"Ox_caps_door." path ->
          emit loc
      | _ -> ()
  in
  {
    base with
    Ast_iterator.module_expr =
      (fun self m ->
        (match m.Parsetree.pmod_desc with Pmod_ident id -> door id.txt id.loc | _ -> ());
        base.module_expr self m);
    module_type =
      (fun self m ->
        (match m.Parsetree.pmty_desc with Pmty_alias id -> door id.txt id.loc | _ -> ());
        base.module_type self m);
    typ =
      (fun self t ->
        (match t.Parsetree.ptyp_desc with
        | Ptyp_constr (id, _) -> door id.txt id.loc
        | _ -> ());
        base.typ self t);
    expr =
      (fun self e ->
        let saved = !potential_authority in
        (match e.Parsetree.pexp_desc with
        | Pexp_function (parameters, _, _) ->
            if
              List.exists
                (fun p ->
                  match p.Parsetree.pparam_desc with
                  | Pparam_val (_, _, pattern) -> (
                      match pattern.ppat_desc with
                      | Ppat_any
                      | Ppat_construct ({ txt = Longident.Lident "()"; _ }, None) ->
                          false
                      | _ -> true)
                  | Pparam_newtype _ -> false)
                parameters
            then potential_authority := true
        | _ -> ());
        (match e.Parsetree.pexp_desc with
        | Pexp_ident id -> (
            (match Syntax.value_origin ~caps context id.txt with
            | Some path when List.mem path targets ->
                if name = "mint" then
                  begin if
                    (not (door_boundary ~caps e.pexp_loc))
                    && not
                         (path = "Ox_test.powerbox"
                         && Caps_policy.declares_test ~caps e.pexp_loc.loc_start.pos_fname
                         )
                  then emit e.pexp_loc
                  end
                else if name = "forge" || not !potential_authority then emit e.pexp_loc
            | _ -> ());
            match id.txt with
            | Longident.Ldot (parent, _) -> door parent.txt e.pexp_loc
            | _ -> ())
        | _ -> ());
        base.expr self e;
        potential_authority := saved);
  }

let boundary ~caps name emit =
  let operation = List.find (fun op -> op.name = name) operations in
  let targets = Paths.values ~caps (resolved_calls operation.calls) in
  let test_mint = Paths.values ~caps [ [ "Ox_test"; "powerbox" ] ] in
  let doors = Paths.modules ~caps [ [ "Ox_caps_door" ] ] in
  let rec door_path en path =
    List.exists (Path.same (Env.normalize_module_path None en path)) doors
    || match path with Path.Pdot (parent, _) -> door_path en parent | _ -> false
  in
  let check path en loc =
    if
      name = "mint"
      && (not (door_boundary ~caps loc))
      && door_path (Paths.env ~caps en) path
    then emit loc
  in
  let base = Tast_iterator.default_iterator in
  {
    base with
    module_expr =
      (fun self m ->
        (match m.mod_desc with
        | Tmod_ident (path, _) -> check path m.mod_env m.mod_loc
        | _ -> ());
        base.module_expr self m);
    module_type =
      (fun self m ->
        (match m.mty_desc with
        | Tmty_alias (path, _) -> check path m.mty_env m.mty_loc
        | _ -> ());
        base.module_type self m);
    typ =
      (fun self t ->
        (match t.ctyp_desc with
        | Ttyp_constr (path, _, _) -> (
            match path with
            | Path.Pdot (parent, _) -> check parent t.ctyp_env t.ctyp_loc
            | _ -> ())
        | _ -> ());
        base.typ self t);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_ident { path = Path.Pdot (parent, _); _ } ->
            check parent e.exp_env e.exp_loc
        | _ -> ());
        if
          Paths.is_value ~caps targets e
          && (name <> "mint"
             || (not (door_boundary ~caps e.exp_loc))
                && not
                     (Paths.is_value ~caps test_mint e
                     && Caps_policy.declares_test ~caps e.exp_loc.loc_start.pos_fname))
        then emit e.exp_loc;
        base.expr self e);
  }

(* ^ncapslint-8jcy: a direct-call closure, not a whole-program call graph.
   Wrapper calls derive the required token rows from their resolved type. *)
let rec token name en ty =
  let name = String.map (function '-' -> '_' | c -> c) name in
  let expected =
    try
      Some
        (let () = () in
         let initial = Lazy.force Env.initial in
         let path, _ =
           Env.lookup_type ~use:false ~loc:Location.none
             (Paths.lid [ "Ox_caps"; "Cap"; "Token"; name ])
             initial
         in
         let expanded =
           Ctype.expand_head initial (Btype.newgenty (Tconstr (path, [], ref Types.Mnil)))
         in
         let original = Env.normalize_type_path None initial path in
         match Types.get_desc expanded with
         | Tconstr (path, _, _) -> [ original; Env.normalize_type_path None initial path ]
         | _ -> [ original ])
    with Not_found | Env.Error _ -> None
  in
  match (expected, Types.get_desc (Ctype.expand_head en ty)) with
  | _, Tpoly (ty, _) -> token name en ty
  | Some expected, Tconstr (path, _, _) ->
      List.exists (Path.same (Env.normalize_type_path None en path)) expected
  | _ -> false

let rec has_cap name en ty =
  let method_name = String.map (function '-' -> '_' | c -> c) name in
  match Types.get_desc (Ctype.expand_head en ty) with
  | Tpoly (ty, _) -> has_cap name en ty
  | Tobject (fields, _) ->
      let rec loop fields =
        match Types.get_desc fields with
        | Tfield (method_, kind, result, rest) ->
            method_ = method_name
            && Types.field_kind_repr kind = Fpublic
            && token name en result
            || loop rest
        | _ -> false
      in
      loop fields
  | _ -> false

(* Payloads carry argument authority. Only visit actual fields/constructor
   arguments: a phantom type parameter does not carry its apparent token.
   Entering a substituted parameter restores its caller's path guard, so finite
   nesting such as [caps option option] is not mistaken for recursive expansion. *)
let argument_has name en ty =
  (* The projection is a graph: compiler AST variants share the same payloads.
     A path-local cycle guard alone unfolds that DAG exponentially. Keep actual
     type arguments in the key so [caps option] and [int option] remain distinct. *)
  let visited = Hashtbl.create 64 in
  let rec loop ((paths, nodes) as seen) substitutions ty =
    let state =
      ( Types.get_id ty,
        List.map
          (fun (parameter, (argument, _)) ->
            (Types.get_id parameter, Types.get_id argument))
          substitutions )
    in
    match
      List.find_opt (fun (parameter, _) -> Types.eq_type parameter ty) substitutions
    with
    | Some (_, (argument, seen)) -> loop seen [] argument
    | None when List.mem (Types.get_id ty) nodes || Hashtbl.mem visited state -> false
    | None -> (
        Hashtbl.add visited state ();
        let next = (paths, Types.get_id ty :: nodes) in
        let instantiate ty =
          match substitutions with
          | [] -> ty
          | _ ->
              let parameters, arguments =
                List.split
                  (List.map
                     (fun (parameter, (argument, _)) -> (parameter, argument))
                     substitutions)
              in
              Ctype.apply en parameters ty arguments
        in
        has_cap name en (instantiate ty)
        ||
        match Types.get_desc ty with
        | Tpoly (ty, _) -> loop next substitutions ty
        | Ttuple fields | Tunboxed_tuple fields ->
            List.exists (fun (_, ty) -> loop next substitutions ty) fields
        | Tvariant row ->
            List.exists
              (fun (_, field) ->
                match Types.row_field_repr field with
                | Rpresent (Some ty) -> loop next substitutions ty
                | Reither (_, types, _) -> List.exists (loop next substitutions) types
                | Rpresent None | Rabsent -> false)
              (Types.row_fields row)
        | Tconstr (path, arguments, _) when not (List.exists (Path.same path) paths) -> (
            let declaration = Env.find_type path en in
            let substitutions =
              List.map2
                (fun parameter argument -> (parameter, (instantiate argument, seen)))
                declaration.type_params arguments
            in
            let payload_has = loop (path :: paths, snd next) substitutions in
            match declaration.type_kind with
            | Type_record (fields, _, _) ->
                List.exists
                  (fun (field : Types.label_declaration) -> payload_has field.ld_type)
                  fields
            | Type_variant (constructors, _, _) ->
                List.exists
                  (fun (constructor : Types.constructor_declaration) ->
                    List.exists payload_has (Types.tys_of_constr_args constructor.cd_args))
                  constructors
            | _ -> Option.fold ~none:false ~some:payload_has declaration.type_manifest)
        | _ -> false)
  in
  try loop ([], []) [] ty with Not_found | Ctype.Cannot_apply -> false

let rec signature_has name en ty =
  match Types.get_desc (Ctype.expand_head en ty) with
  | Tpoly (ty, _) -> signature_has name en ty
  | Tarrow (_, arg, result, _) -> argument_has name en arg || signature_has name en result
  | _ -> false

let signature_for ~caps ?operation emit =
  let raw_targets =
    List.filter_map
      (fun op ->
        if op.name = "mint" || op.name = "forge" then None
        else Some (op.name, Paths.values ~caps (resolved_calls op.calls)))
      operations
  in
  let wrappers =
    Paths.modules ~caps
      [ [ "Ox_caps"; "Cap_unix" ]; [ "Ox_caps"; "Cap_sys" ]; [ "Ox_caps"; "Cap_stdlib" ] ]
  in
  let tuple_projections =
    Paths.values ~caps [ [ "Stdlib"; "fst" ]; [ "Stdlib"; "snd" ] ]
  in
  let result_binds =
    Paths.values ~caps [ [ "Result"; "bind" ]; [ "Stdlib"; "Result"; "bind" ] ]
  in
  let base = Tast_iterator.default_iterator in
  let arguments_in_scope = ref [] and functions = ref [] and bind_aliases = ref [] in
  let scoped f =
    let saved = (!arguments_in_scope, !functions, !bind_aliases) in
    Fun.protect
      ~finally:(fun () ->
        let args, fns, binds = saved in
        arguments_in_scope := args;
        functions := fns;
        bind_aliases := binds)
      f
  in
  let is_result_bind path en =
    let path = Env.normalize_value_path None en path in
    List.exists (Path.same path) result_binds
    ||
    match path with
    | Path.Pident id -> List.exists (Ident.same id) !bind_aliases
    | _ -> false
  in
  let payloads e =
    match e.exp_desc with
    | Texp_construct (_, _, _, args, _) -> Some (List.map snd args)
    | Texp_tuple (args, _) -> Some (List.map snd args)
    | Texp_variant (_, payload) -> Some (Option.to_list (Option.map fst payload))
    | _ -> None
  in
  let rec carries_authority e =
    match payloads e with
    | Some payloads -> List.exists carries_authority payloads
    | None ->
        List.exists
          (fun (name, _) -> argument_has name (Paths.env ~caps e.exp_env) e.exp_type)
          raw_targets
  in
  let rec from_argument e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } ->
        List.exists (Ident.same id) !arguments_in_scope
    | Texp_field { record; _ } -> from_argument record
    | Texp_apply (projection, [ (Nolabel, Arg (pair, _)) ], _, _, _)
      when Paths.is_value ~caps tuple_projections projection ->
        from_argument pair
    | Texp_match (source, _, cases, _, _) when from_argument source ->
        (* Empty/Error branches carry no authority; every branch that does must
           preserve the parameter root. Exception patterns are never rooted. *)
        List.exists (fun case -> carries_authority case.c_rhs) cases
        && List.for_all
             (fun case ->
               (not (carries_authority case.c_rhs))
               || scoped (fun () ->
                   (match Typedtree.split_pattern case.c_lhs with
                   | Some pattern, None ->
                       arguments_in_scope :=
                         Typedtree.pat_bound_idents pattern @ !arguments_in_scope
                   | _ -> ());
                   from_argument case.c_rhs))
             cases
    | _ -> (
        match payloads e with
        | Some payloads ->
            let authority = List.filter carries_authority payloads in
            authority <> [] && List.for_all from_argument authority
        | None -> false)
  in
  let exposed name en =
    List.exists
      (fun fn -> signature_has name (Paths.env ~caps fn.exp_env) fn.exp_type)
      !functions
    || List.exists
         (fun id ->
           try
             argument_has name en
               (Subst.Lazy.force_type_expr (Env.find_value (Path.Pident id) en).val_type)
           with Not_found -> false)
         !arguments_in_scope
  in
  let report e =
    match !functions with fn :: _ -> emit fn.exp_loc | [] -> emit e.exp_loc
  in
  {
    base with
    expr =
      (fun self e ->
        scoped (fun () ->
            (match e.exp_desc with
            | Texp_function { params; body; _ } ->
                let ids =
                  List.concat_map
                    (fun p ->
                      let pattern =
                        match p.fp_kind with
                        | Tparam_pat p | Tparam_optional_default (p, _, _) -> p
                      in
                      p.fp_param :: Typedtree.pat_bound_idents pattern)
                    params
                in
                let ids =
                  match body with
                  | Tfunction_cases cases ->
                      cases.fc_param
                      :: List.concat_map
                           (fun c -> Typedtree.pat_bound_idents c.c_lhs)
                           cases.fc_cases
                      @ ids
                  | _ -> ids
                in
                arguments_in_scope := ids @ !arguments_in_scope;
                functions := e :: !functions
            | Texp_let (_, bindings, _) ->
                List.iter
                  (fun binding ->
                    let ids = Typedtree.pat_bound_idents binding.vb_pat in
                    if from_argument binding.vb_expr then
                      arguments_in_scope := ids @ !arguments_in_scope;
                    match binding.vb_expr.exp_desc with
                    | Texp_ident { path; _ }
                      when is_result_bind path (Paths.env ~caps binding.vb_expr.exp_env)
                      ->
                        bind_aliases := ids @ !bind_aliases
                    | _ -> ())
                  bindings
            | Texp_letop { let_; ands = []; param; body; _ }
              when is_result_bind let_.bop_op_path (Paths.env ~caps e.exp_env)
                   && from_argument let_.bop_exp ->
                arguments_in_scope :=
                  (param :: Typedtree.pat_bound_idents body.c_lhs) @ !arguments_in_scope
            | Texp_match (source, _, cases, _, _) when from_argument source ->
                List.iter
                  (fun case ->
                    (* Exceptions/effects are not projections of the scrutinee. *)
                    match Typedtree.split_pattern case.c_lhs with
                    | Some pattern, None ->
                        arguments_in_scope :=
                          Typedtree.pat_bound_idents pattern @ !arguments_in_scope
                    | _ -> ())
                  cases
            | Texp_apply (callee, args, _, _, _) ->
                if Paths.in_module ~caps wrappers callee then begin
                  let en = Paths.env ~caps callee.exp_env in
                  let cap =
                    List.find_map
                      (function Labelled "caps", Arg (cap, _) -> Some cap | _ -> None)
                      args
                  in
                  List.iter
                    (fun (name, _) ->
                      if
                        (match operation with
                          | None -> true
                          | Some selected -> name = selected)
                        && signature_has name en callee.exp_type
                        &&
                        match cap with
                        | None -> false
                        | Some cap ->
                            not
                              (from_argument cap
                              && has_cap name (Paths.env ~caps cap.exp_env) cap.exp_type)
                      then report e)
                    raw_targets
                end
            | Texp_ident _ ->
                List.iter
                  (fun (name, targets) ->
                    if
                      (match operation with
                        | None -> true
                        | Some selected -> name = selected)
                      && Paths.is_value ~caps targets e
                      && not (exposed name (Paths.env ~caps e.exp_env))
                    then report e)
                  raw_targets
            | _ -> ());
            base.expr self e));
  }

let signature ~caps emit = signature_for ~caps emit

let raw ~caps name emit =
  if name = "mint" || name = "forge" then boundary ~caps name emit
  else signature_for ~caps ~operation:name emit
