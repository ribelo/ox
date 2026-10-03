(* Throwaway suspension-cost AST collector; pinned OxCaml compiler-libs. *)
open Parsetree
let s x = `String x
let i x = `Int x
let emit fields = print_endline (Yojson.Basic.to_string (`Assoc fields))
let file = ref ""
let modpath = ref ""
let owner = ref ""
let opens = ref []
let calls = ref 0
let line loc = loc.Location.loc_start.Lexing.pos_lnum
let stop loc = loc.Location.loc_end.Lexing.pos_lnum
let rec lid = function Longident.Lident n -> n | Ldot (a,n) -> lid a.txt ^ "." ^ n.txt | Lapply (a,b) -> lid a.txt ^ "(" ^ lid b.txt ^ ")"
let rec pname p = match p.ppat_desc with Ppat_var n -> Some n.txt | Ppat_constraint (p,_,_) | Ppat_alias (p,_) -> pname p | _ -> None
let rec unwrap e = match e.pexp_desc with Pexp_constraint(e,_,_) | Pexp_coerce(e,_,_) -> unwrap e | _ -> e
let rec ename e = match (unwrap e).pexp_desc with Pexp_ident n -> lid n.txt | Pexp_field(e,n) -> ename e ^ "." ^ lid n.txt | Pexp_apply(e,_) -> ename e | _ -> "<expr>"
let info loc = ["file",s !file; "module",s !modpath; "owner",s !owner; "line",i (line loc); "end",i (stop loc); "opens",`List(List.map s !opens)]
let isfun e = match (unwrap e).pexp_desc with Pexp_function _ -> true | _ -> false
let isalias e = match (unwrap e).pexp_desc with Pexp_ident _ -> true | _ -> false
let base = Ast_iterator.default_iterator
let iterator = { base with
  attribute = (fun _ _ -> ());
  value_binding = (fun self vb ->
    match pname vb.pvb_pat with
    | Some name when isfun vb.pvb_expr || isalias vb.pvb_expr ->
        let parent = !owner in
        let id = !file ^ ":" ^ string_of_int(line vb.pvb_loc) ^ ":" ^ name in
        emit (("kind",s "function")::("id",s id)::("name",s name)::("parent",s parent)::("alias",`Bool(isalias vb.pvb_expr))::info vb.pvb_loc);
        owner := id; base.value_binding self vb; owner := parent
    | _ -> base.value_binding self vb);
  module_binding = (fun self mb ->
    let previous = !modpath in let previous_opens = !opens in
    let name = Option.value mb.pmb_name.txt ~default:"<anonymous>" in
    (match mb.pmb_expr.pmod_desc with Pmod_ident n -> emit (("kind",s "module_alias")::("name",s name)::("target",s(lid n.txt))::info mb.pmb_loc) | _ -> ());
    modpath := previous ^ "." ^ name; base.module_binding self mb; modpath := previous; opens := previous_opens);
  open_declaration = (fun self od ->
    (match od.popen_expr.pmod_desc with Pmod_ident n -> opens := lid n.txt :: !opens | _ -> ());
    base.open_declaration self od);
  expr = (fun self e ->
    match e.pexp_desc with
    | Pexp_open (od, body) ->
        let old = !opens in self.open_declaration self od; self.expr self body; opens := old
    | Pexp_apply (fn,args) ->
        incr calls;
        emit (("kind",s "call")::("callee",s(ename fn))::("position",i e.pexp_loc.loc_start.pos_cnum)::("arguments",`List(List.map(fun(label,arg)->`Assoc["label",s(match label with Asttypes.Nolabel->"" | Labelled n->n | Optional n->"?"^n);"name",s(ename arg);"function",`Bool(isfun arg);"line",i(line arg.pexp_loc);"end",i(stop arg.pexp_loc);"startpos",i arg.pexp_loc.loc_start.pos_cnum;"endpos",i arg.pexp_loc.loc_end.pos_cnum])args))::info e.pexp_loc);
        (match (unwrap fn).pexp_desc with Pexp_ident _ -> () | Pexp_field (base, _) -> self.expr self base | _ -> self.expr self fn);
        List.iter(fun(_,arg)->self.expr self arg)args
    | Pexp_field _ -> emit (("kind",s "reference")::("callee",s(ename e))::("position",i e.pexp_loc.loc_start.pos_cnum)::info e.pexp_loc); base.expr self e
    | Pexp_ident n -> emit (("kind",s "reference")::("callee",s(lid n.txt))::("position",i e.pexp_loc.loc_start.pos_cnum)::info e.pexp_loc)
    | _ -> base.expr self e)
}
let () =
  for arg = 1 to Array.length Sys.argv - 1 do
    file := Sys.argv.(arg); modpath := String.capitalize_ascii(Filename.remove_extension(Filename.basename !file)); owner := ""; opens := [];
    let ch = open_in !file in let lb = Lexing.from_channel ch in Location.init lb !file;
    try let tree = Parse.implementation lb in close_in ch; iterator.structure iterator tree
    with ex -> close_in_noerr ch; Location.report_exception Format.err_formatter ex; exit 1
  done
