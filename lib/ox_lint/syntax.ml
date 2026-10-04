(* ^nlint-rv8u: census-style traversal with scoped opens and aliases. *)
open Ocaml_common
open Parsetree

type context = { mutable opens : string list; mutable aliases : (string * string) list }

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
  let text = expand context (name lid) in
  if String.contains text '.' then [ text ]
  else List.map (fun opened -> opened ^ "." ^ text) context.opens @ [ text ]

let scoped context f =
  let opens, aliases = (context.opens, context.aliases) in
  Fun.protect
    ~finally:(fun () ->
      context.opens <- opens;
      context.aliases <- aliases)
    f

let walk path make =
  let context = { opens = [ "Stdlib" ]; aliases = [] } in
  let base = Ast_iterator.default_iterator in
  let iterator =
    {
      base with
      structure = (fun self items -> scoped context (fun () -> base.structure self items));
      signature = (fun self items -> scoped context (fun () -> base.signature self items));
      module_binding =
        (fun self mb ->
          base.module_binding self mb;
          match (mb.pmb_name.txt, mb.pmb_expr.pmod_desc) with
          | Some alias, Pmod_ident target ->
              context.aliases <-
                (alias, expand context (name target.txt)) :: context.aliases
          | Some alias, _ -> context.aliases <- List.remove_assoc alias context.aliases
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
                      context.aliases <- List.remove_assoc alias context.aliases
                  | _ -> ())
              | _ -> ());
              base.expr self e));
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
