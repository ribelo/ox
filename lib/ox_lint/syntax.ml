(* ^nlint-rv8u: census-style traversal with scoped opens and aliases. *)
open Ocaml_common
open Parsetree

(* ^ncapslint-nf4t: source identity tracks value binders and local module exports.
   resolve retains the older candidate API; value_origin is the capability decider. *)
type context = {
  mutable opens : string list;
  mutable aliases : (string * string) list;
  mutable values : string list;
  mutable locals : (string * string list) list;
}

let rec bound pattern =
  let names = ref [] in
  let base = Ast_iterator.default_iterator in
  let iterator =
    {
      base with
      pat =
        (fun self p ->
          (match p.ppat_desc with
          | Ppat_var n | Ppat_alias (_, n) -> names := n.txt :: !names
          | _ -> ());
          base.pat self p);
    }
  in
  iterator.pat iterator pattern;
  !names

let exports items =
  List.concat_map
    (fun item ->
      match item.pstr_desc with
      | Pstr_value (_, bindings) -> List.concat_map (fun vb -> bound vb.pvb_pat) bindings
      | Pstr_primitive value -> [ value.pval_name.txt ]
      | _ -> [])
    items

let known_export module_ value =
  try
    ignore
      (Env.lookup_value ~use:false ~loc:Location.none
         (Option.get
            (Longident.unflatten (String.split_on_char '.' (module_ ^ "." ^ value))))
         (Lazy.force Env.initial));
    true
  with Not_found | Env.Error _ -> false

let rec name = function
  | Longident.Lident n -> n
  | Ldot (p, n) -> name p.txt ^ "." ^ n.txt
  | Lapply (a, b) -> name a.txt ^ "(" ^ name b.txt ^ ")"

let expand context text =
  let rec loop seen text =
    let head, tail =
      match String.index_opt text '.' with
      | None -> (text, "")
      | Some i -> (String.sub text 0 i, String.sub text i (String.length text - i))
    in
    match List.assoc_opt head context.aliases with
    | Some target when not (List.mem head seen) -> loop (head :: seen) (target ^ tail)
    | _ -> text
  in
  loop [] text

let resolve context lid =
  let visible text =
    if String.starts_with ~prefix:"@local." text then
      String.sub text 7 (String.length text - 7)
    else text
  in
  let text = visible (expand context (name lid)) in
  if String.contains text '.' then [ text ]
  else List.map (fun opened -> visible opened ^ "." ^ text) context.opens @ [ text ]

let module_origin context lid =
  let text = expand context (name lid) in
  if String.starts_with ~prefix:"@local." text then None else Some text

let value_origin context lid =
  let text = expand context (name lid) in
  if String.contains text '.' then
    if String.starts_with ~prefix:"@local." text then None
    else if
      String.starts_with ~prefix:"Stdlib." text
      && String.length text > 7
      && text.[7] >= 'A'
      && text.[7] <= 'Z'
    then Some (String.sub text 7 (String.length text - 7))
    else Some text
  else if List.mem text context.values then None
  else
    let rec lookup = function
      | [] -> Some text
      | module_ :: rest -> (
          match List.assoc_opt module_ context.locals with
          | Some names when List.mem text names -> None
          | Some _ -> lookup rest
          | None ->
              if known_export module_ text then Some (module_ ^ "." ^ text)
              else lookup rest)
    in
    lookup context.opens

let scoped context f =
  let opens, aliases, values, locals =
    (context.opens, context.aliases, context.values, context.locals)
  in
  Fun.protect
    ~finally:(fun () ->
      context.opens <- opens;
      context.aliases <- aliases;
      context.values <- values;
      context.locals <- locals)
    f

let walk path make =
  (* ^ncapslint-nf4t: source resolution needs only the compiler standard interfaces,
     never a consumer build artifact or the last annotation's load path. *)
  Envaux.reset_cache ~preserve_persistent_env:false;
  Load_path.init ~auto_include:Load_path.no_auto_include ~hidden:[]
    ~visible:
      (List.map
         (fun path -> { Clflags.path; cmx_guaranteed = false })
         [ Config.standard_library; Filename.concat Config.standard_library "unix" ]);
  let context = { opens = [ "Stdlib" ]; aliases = []; values = []; locals = [] } in
  let base = Ast_iterator.default_iterator in
  let iterator =
    {
      base with
      structure = (fun self items -> scoped context (fun () -> base.structure self items));
      signature = (fun self items -> scoped context (fun () -> base.signature self items));
      structure_item =
        (fun self item ->
          let names =
            match item.pstr_desc with
            | Pstr_value (_, bindings) ->
                List.concat_map (fun vb -> bound vb.pvb_pat) bindings
            | Pstr_primitive value -> [ value.pval_name.txt ]
            | _ -> []
          in
          (match item.pstr_desc with
          | Pstr_value (Recursive, _) -> context.values <- names @ context.values
          | _ -> ());
          base.structure_item self item;
          context.values <- names @ context.values);
      module_binding =
        (fun self mb ->
          base.module_binding self mb;
          match (mb.pmb_name.txt, mb.pmb_expr.pmod_desc) with
          | Some alias, Pmod_ident target ->
              context.aliases <-
                (alias, expand context (name target.txt)) :: context.aliases
          | Some alias, Pmod_structure items ->
              let local = "@local." ^ alias in
              context.aliases <- (alias, local) :: context.aliases;
              context.locals <- (local, exports items) :: context.locals
          | Some alias, _ ->
              context.aliases <- (alias, "@local." ^ alias) :: context.aliases
          | _ -> ());
      module_declaration =
        (fun self md ->
          base.module_declaration self md;
          match (md.pmd_name.txt, md.pmd_type.pmty_desc) with
          | Some alias, Pmty_alias target ->
              context.aliases <-
                (alias, expand context (name target.txt)) :: context.aliases
          | Some alias, _ -> context.aliases <- List.remove_assoc alias context.aliases
          | _ -> ());
      open_declaration =
        (fun self od ->
          base.open_declaration self od;
          match od.popen_expr.pmod_desc with
          | Pmod_ident target ->
              context.opens <- expand context (name target.txt) :: context.opens
          | _ -> ());
      open_description =
        (fun self od ->
          base.open_description self od;
          context.opens <- expand context (name od.popen_expr.txt) :: context.opens);
      expr =
        (fun self e ->
          scoped context (fun () ->
              (match e.pexp_desc with
              | Pexp_letmodule (alias, m, _) -> (
                  match (alias.txt, m.pmod_desc) with
                  | Some alias, Pmod_ident target ->
                      context.aliases <-
                        (alias, expand context (name target.txt)) :: context.aliases
                  | Some alias, _ ->
                      context.aliases <- (alias, "@local." ^ alias) :: context.aliases
                  | _ -> ())
              | _ -> ());
              match e.pexp_desc with
              | Pexp_let (_, recursive, bindings, body) ->
                  let names = List.concat_map (fun vb -> bound vb.pvb_pat) bindings in
                  if recursive = Recursive then context.values <- names @ context.values;
                  List.iter (self.value_binding self) bindings;
                  context.values <- names @ context.values;
                  self.expr self body
              | Pexp_function (params, _, body) -> (
                  List.iter
                    (fun param ->
                      match param.pparam_desc with
                      | Pparam_val (_, default, pattern) ->
                          Option.iter (self.expr self) default;
                          self.pat self pattern;
                          context.values <- bound pattern @ context.values
                      | _ -> ())
                    params;
                  match body with
                  | Pfunction_body body -> self.expr self body
                  | Pfunction_cases (cases, _, _) -> List.iter (self.case self) cases)
              | Pexp_open (opened, body) ->
                  self.open_declaration self opened;
                  self.expr self body
              | _ -> base.expr self e));
      case =
        (fun self case ->
          scoped context (fun () ->
              self.pat self case.pc_lhs;
              context.values <- bound case.pc_lhs @ context.values;
              Option.iter (self.expr self) case.pc_guard;
              self.expr self case.pc_rhs));
    }
  in
  let iterator : Ast_iterator.iterator = make context iterator in
  Lexer.handle_docstrings := true;
  Docstrings.init ();
  Lexer.init ();
  let channel = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let lexbuf = Lexing.from_channel channel in
      Location.init lexbuf path;
      if Filename.check_suffix path ".mli" then
        iterator.signature iterator (Parse.interface lexbuf)
      else iterator.structure iterator (Parse.implementation lexbuf))
