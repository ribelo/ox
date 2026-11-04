(** See [Expand.mli]. *)

open Ocaml_common
open Parsetree

let ghost loc = { loc with Location.loc_ghost = true }

let ox_result ~loc name =
  Ast_helper.Exp.ident ~loc
    { txt = Option.get (Longident.unflatten [ "Ox"; "Result"; name ]); loc }

let nontail ~loc = Ast_helper.Attr.mk ~loc { txt = "nontail"; loc } (PStr [])

(* The parser's own [fun x -> ()] supplies an empty function constraint, so the
   expansion carries no hand-built mode or type annotation. *)
let empty_constraint =
  lazy
    (match (Parse.expression (Lexing.from_string "fun x -> ()")).pexp_desc with
    | Pexp_function (_, constraint_, _) -> constraint_
    | _ -> assert false)

let lambda ~loc pat body =
  Ast_helper.Exp.function_ ~loc
    [ { pparam_loc = pat.ppat_loc; pparam_desc = Pparam_val (Nolabel, None, pat) } ]
    (Lazy.force empty_constraint) (Pfunction_body body)

let refuse ~loc fmt = Location.raise_errorf ~loc fmt

let check_binding op vb =
  if vb.pvb_is_poly then
    refuse ~loc:vb.pvb_loc "let%%%s: poly_ bindings are not supported" op;
  if Option.is_some vb.pvb_constraint then
    refuse ~loc:vb.pvb_loc
      "let%%%s: a constraint after the pattern is not supported; write (PATTERN : TYPE)"
      op;
  if vb.pvb_modes <> [] then
    refuse ~loc:vb.pvb_loc "let%%%s: mode annotations on the binding are not supported" op

(* [let%op p1 = e1 and p2 = e2 and ... in body] binds the tuple of [Ox.Result.both]. *)
let rec combine = function
  | [] -> assert false
  | [ vb ] -> (vb.pvb_expr, vb.pvb_pat)
  | vb :: rest ->
      let expr, pat = combine rest in
      let loc = ghost vb.pvb_loc in
      ( Ast_helper.Exp.apply ~loc (ox_result ~loc "both")
          [ (Nolabel, vb.pvb_expr); (Nolabel, expr) ],
        Ast_helper.Pat.tuple ~loc [ (None, vb.pvb_pat); (None, pat) ] Closed )

let expand ~loc op vbs body =
  let rhs, pat = combine vbs in
  let loc = ghost loc in
  Ast_helper.Exp.apply ~loc
    ~attrs:[ nontail ~loc ]
    (ox_result ~loc op)
    [ (Nolabel, rhs); (Nolabel, lambda ~loc pat body) ]

let expr (self : Ast_mapper.mapper) (e : expression) =
  match e.pexp_desc with
  | Pexp_extension ({ txt = ("bind" | "map") as op; loc }, payload) -> (
      match payload with
      | PStr
          [
            {
              pstr_desc =
                Pstr_eval
                  ( {
                      pexp_desc = Pexp_let (Immutable, Nonrecursive, vbs, body);
                      pexp_attributes = [];
                      _;
                    },
                    [] );
              _;
            };
          ] ->
          List.iter (check_binding op) vbs;
          let vbs =
            List.map (fun vb -> { vb with pvb_expr = self.expr self vb.pvb_expr }) vbs
          in
          expand ~loc:e.pexp_loc op vbs (self.expr self body)
      | _ -> refuse ~loc "%%%s expects let%%%s PATTERN = EXPR in BODY" op op)
  | _ -> Ast_mapper.default_mapper.expr self e

let mapper = { Ast_mapper.default_mapper with expr }

let has_substring needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec go i = i + n <= h && (String.sub haystack i n = needle || go (i + 1)) in
  go 0

let lexbuf_of ~filename source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf filename;
  lexbuf

let marshalled ~magic ~filename ast =
  String.concat ""
    [ magic; Marshal.to_string (filename : string) []; Marshal.to_string ast [] ]

let process ~filename ~source =
  if not (has_substring "%bind" source || has_substring "%map" source) then Ok source
  else
    match
      if Filename.check_suffix filename ".mli" then
        let ast = Parse.interface (lexbuf_of ~filename source) in
        marshalled ~magic:Config.ast_intf_magic_number ~filename
          (mapper.signature mapper ast)
      else
        let ast = Parse.implementation (lexbuf_of ~filename source) in
        marshalled ~magic:Config.ast_impl_magic_number ~filename
          (mapper.structure mapper ast)
    with
    | output -> Ok output
    | exception (Syntaxerr.Error _ | Lexer.Error _) -> Ok source
    | exception exn -> (
        match Location.error_of_exn exn with
        | Some (`Ok report) -> Error (Format.asprintf "%a" Location.print_report report)
        | Some `Already_displayed | None -> raise exn)
