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

let entry loc =
  let parts = String.split_on_char '/' loc.Location.loc_start.Lexing.pos_fname in
  List.mem "bin" parts && List.hd (List.rev parts) = "main.ml"

let door_boundary loc =
  let path = Caps_policy.policy_path loc.Location.loc_start.Lexing.pos_fname in
  String.starts_with ~prefix:"lib/caps/" path
  || List.mem path [ "lib/app/ox_app.ml"; "lib/test/ox_test.ml" ]

let arguments args = List.filter_map (function _, Arg (e, _) -> Some e | _ -> None) args

let door_exit e =
  match e.exp_desc with
  | Texp_apply (fn, args, _, _, _) -> (
      Paths.is_value (Paths.values [ [ "Stdlib"; "exit" ] ]) fn
      &&
      match arguments args with
      | [ { exp_desc = Texp_apply (door, _, _, _, _); _ } ] ->
          Paths.in_module (Paths.modules [ [ "Ox_app" ] ]) door
      | _ -> false)
  | _ -> false

(* ^ncapslint-nf4t ^ncapslint-87ld: mandatory compiler-parser source tier.
   The source symbol table resolves opens, module aliases and local binders;
   opaque external re-exports are a typed-tier responsibility. *)
let source name emit context (base : Ast_iterator.iterator) =
  let op = List.find (fun op -> op.name = name) operations in
  let targets = List.map (String.concat ".") op.calls in
  let origin e =
    match e.Parsetree.pexp_desc with
    | Pexp_ident id -> Syntax.value_origin context id.txt
    | _ -> None
  in
  let door_exit e =
    match e.Parsetree.pexp_desc with
    | Pexp_apply (fn, [ (_, { pexp_desc = Pexp_apply (door, _); _ }) ]) -> (
        origin fn = Some "Stdlib.exit"
        &&
        match origin door with
        | Some path -> String.starts_with ~prefix:"Ox_app." path
        | None -> false)
    | _ -> false
  in
  let door id loc =
    if name = "mint" && not (door_boundary loc) then
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
        if name = "exit" && door_exit e then
          match e.Parsetree.pexp_desc with
          | Pexp_apply (_, args) -> List.iter (fun (_, arg) -> self.expr self arg) args
          | _ -> assert false
        else begin
          (match e.Parsetree.pexp_desc with
          | Pexp_ident id -> door id.txt id.loc
          | _ -> ());
          (match origin e with
          | Some path
            when List.mem path targets
                 && not
                      (name = "mint" && path = "Ox_app.with_powerbox" && entry e.pexp_loc)
            ->
              emit e.pexp_loc
          | _ -> ());
          base.expr self e
        end);
  }

let raw name emit =
  let operation = List.find (fun op -> op.name = name) operations in
  let targets = Paths.values (resolved_calls operation.calls) in
  let with_powerbox = Paths.values [ [ "Ox_app"; "with_powerbox" ] ] in
  let doors = Paths.modules [ [ "Ox_caps_door" ] ] in
  let rec door_path en path =
    List.exists (Path.same (Env.normalize_module_path None en path)) doors
    || match path with Path.Pdot (parent, _) -> door_path en parent | _ -> false
  in
  let check path en loc =
    if name = "mint" && (not (door_boundary loc)) && door_path (Paths.env en) path then
      emit loc
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
        if name = "exit" && door_exit e then
          match e.exp_desc with
          | Texp_apply (_, args, _, _, _) -> List.iter (self.expr self) (arguments args)
          | _ -> assert false
        else begin
          (match e.exp_desc with
          | Texp_ident { path = Path.Pdot (parent, _); _ } ->
              check parent e.exp_env e.exp_loc
          | _ -> ());
          if
            Paths.is_value targets e
            && not (name = "mint" && entry e.exp_loc && Paths.is_value with_powerbox e)
          then emit e.exp_loc;
          base.expr self e
        end);
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

(* A closed deps record is an argument, not ambient authority. Follow record
   fields, bounded by type-path identity so recursive records terminate. *)
let rec argument_has name en seen ty =
  has_cap name en ty
  ||
  match Types.get_desc (Ctype.expand_head en ty) with
  | Tpoly (ty, _) -> argument_has name en seen ty
  | Tconstr (path, _, _) when not (List.exists (Path.same path) seen) -> (
      match (Env.find_type path en).type_kind with
      | Type_record (fields, _, _) ->
          List.exists
            (fun (field : Types.label_declaration) ->
              argument_has name en (path :: seen) field.ld_type)
            fields
      | _ -> false)
  | _ -> false

let rec signature_has name en ty =
  match Types.get_desc (Ctype.expand_head en ty) with
  | Tpoly (ty, _) -> signature_has name en ty
  | Tarrow (_, arg, result, _) ->
      argument_has name en [] arg || signature_has name en result
  | _ -> false

let signature emit =
  let raw_targets =
    List.filter_map
      (fun op ->
        if op.name = "mint" || op.name = "forge" then None
        else Some (op.name, Paths.values (resolved_calls op.calls)))
      operations
  in
  let wrappers =
    Paths.modules
      [ [ "Ox_caps"; "Cap_unix" ]; [ "Ox_caps"; "Cap_sys" ]; [ "Ox_caps"; "Cap_stdlib" ] ]
  in
  let base = Tast_iterator.default_iterator in
  let arguments_in_scope = ref [] and functions = ref [] in
  let scoped f =
    let saved = (!arguments_in_scope, !functions) in
    Fun.protect
      ~finally:(fun () ->
        let args, fns = saved in
        arguments_in_scope := args;
        functions := fns)
      f
  in
  let rec from_argument e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } ->
        List.exists (Ident.same id) !arguments_in_scope
    | Texp_field { record; _ } -> from_argument record
    | _ -> false
  in
  let exposed name =
    List.exists
      (fun fn -> signature_has name (Paths.env fn.exp_env) fn.exp_type)
      !functions
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
                    if from_argument binding.vb_expr then
                      arguments_in_scope :=
                        Typedtree.pat_bound_idents binding.vb_pat @ !arguments_in_scope)
                  bindings
            | Texp_apply (callee, args, _, _, _) when not (door_exit e) ->
                if Paths.in_module wrappers callee then begin
                  let en = Paths.env callee.exp_env in
                  let cap =
                    List.find_map
                      (function Labelled "caps", Arg (cap, _) -> Some cap | _ -> None)
                      args
                  in
                  List.iter
                    (fun (name, _) ->
                      if
                        signature_has name en callee.exp_type
                        &&
                        match cap with
                        | None -> false
                        | Some cap ->
                            not
                              (from_argument cap
                              && has_cap name (Paths.env cap.exp_env) cap.exp_type)
                      then report e)
                    raw_targets
                end
            | Texp_ident _ ->
                List.iter
                  (fun (name, targets) ->
                    if Paths.is_value targets e && not (exposed name) then report e)
                  raw_targets
            | _ -> ());
            if door_exit e then
              match e.exp_desc with
              | Texp_apply (_, args, _, _, _) ->
                  List.iter (self.expr self) (arguments args)
              | _ -> assert false
            else base.expr self e));
  }
