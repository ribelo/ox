(* THROWAWAY: interface/docstrings/modes probe for pinned OxCaml compiler-libs. *)
open Parsetree
let s x = `String x
let i x = `Int x
let emit xs = print_endline (Yojson.Basic.to_string (`Assoc xs))
let pos p = `Assoc ["line",i p.Lexing.pos_lnum; "column",i (p.pos_cnum - p.pos_bol); "byte",i p.pos_cnum]
let span l = `Assoc ["file",s l.Location.loc_start.pos_fname; "start",pos l.loc_start; "end",pos l.loc_end; "ghost",`Bool l.loc_ghost]
let docs attrs = `List (List.filter_map (fun a ->
  if a.attr_name.txt <> "ocaml.doc" then None else
  match a.attr_payload with
  | PStr [{pstr_desc=Pstr_eval ({pexp_desc=Pexp_constant {pconst_desc=Pconst_string(text,_,_); _}; _},_); _}] ->
      Some (`Assoc ["text",s text; "span",span a.attr_loc])
  | _ -> failwith "unexpected ocaml.doc payload") attrs)
let names attrs = `List (List.map (fun a -> s a.attr_name.txt) attrs)
let owner = ref ""
let input = ref ""
let with_owner name f = let old = !owner in owner := name; Fun.protect ~finally:(fun () -> owner := old) f
let basefields kind loc = ["kind",s kind; "input",s !input; "owner",s !owner; "span",span loc]
let pname p = match p.ppat_desc with Ppat_var n -> n.txt | _ -> "<pattern>"
let pbase = Ast_iterator.default_iterator
let piter = { pbase with
  attribute=(fun _ _ -> ());
  value_description=(fun self v -> with_owner v.pval_name.txt (fun () ->
    emit (["name",s v.pval_name.txt; "type",s (Format.asprintf "%a" Pprintast.core_type v.pval_type);
           "docs",docs v.pval_attributes; "attributes",names v.pval_attributes;
           "primitive",`Bool (v.pval_prim <> [])] @ basefields "source_val" v.pval_loc);
    pbase.value_description self v));
  value_binding=(fun self v -> with_owner (pname v.pvb_pat) (fun () -> pbase.value_binding self v));
  modes=(fun _ modes -> List.iter (fun m -> let Mode text = m.Location.txt in
    emit (["text",s text] @ basefields "source_mode" m.loc)) modes);
  modalities=(fun _ modes -> List.iter (fun m -> let Modality text = m.Location.txt in
    emit (["text",s text] @ basefields "source_modality" m.loc)) modes);
}
let atom a = match a with Mode.Alloc.Atom (axis,value) ->
  Format_doc.asprintf "%a" (Mode.Alloc.Const.print_axis axis) value
let mode_desc xs = `List (List.map (fun a -> `Assoc ["text",s (atom a.Location.txt); "span",span a.loc]) xs)
let locality m = s (match m.Mode.Alloc.areality with Mode.Locality.Const.Global -> "global" | Local -> "local")
let const_mode m = s (Format_doc.asprintf "%a" Mode.Alloc.Const.print m)
let variable_mode m = s (Format_doc.asprintf "%a" (Mode.Alloc.print ~verbose:false ()) m)
let modality_atom a = match a with Mode.Modality.Atom (axis,value) ->
  Format_doc.asprintf "%a" Mode.Modality.Const.print (Mode.Modality.Const.set axis value Mode.Modality.Const.id)
let typed_modalities v = match v.Typedtree.val_modal_info with
  | Valmi_sig_value m -> `Assoc ["effective",s (Format_doc.asprintf "%a" Mode.Modality.Const.print m.moda_modalities);
       "written",`List (List.map (fun a -> `Assoc ["text",s (modality_atom a.Location.txt); "span",span a.loc]) m.moda_desc)]
  | Valmi_str_primitive m -> `Assoc ["written",mode_desc m.mode_desc]
let typed_field d =
  let m = d.Typedtree.ld_modalities in
  emit (["name",s d.ld_name.txt; "effective",s (Format_doc.asprintf "%a" Mode.Modality.Const.print m.moda_modalities);
    "written",`List (List.map (fun a -> `Assoc ["text",s (modality_atom a.Location.txt); "span",span a.loc]) m.moda_desc)] @ basefields "typed_field_modality" d.ld_loc)
let tbase = Tast_iterator.default_iterator
let titer = { tbase with
  attribute=(fun _ _ -> ());
  value_description=(fun self v -> with_owner v.Typedtree.val_name.txt (fun () ->
    emit (["name",s v.val_name.txt; "type",s (Format.asprintf "%a" Printtyp.type_scheme v.val_desc.ctyp_type);
           "docs",docs v.val_attributes; "attributes",names v.val_attributes;
           "types_docs",docs v.val_val.val_attributes; "modalities",typed_modalities v] @ basefields "typed_val" v.val_loc);
    tbase.value_description self v));
  type_declaration=(fun self t ->
    (match t.Typedtree.typ_kind with
     | Ttype_record ds | Ttype_record_unboxed_product ds -> List.iter typed_field ds
     | Ttype_variant cs -> List.iter (fun c -> match c.Typedtree.cd_args with Cstr_record ds -> List.iter typed_field ds | Cstr_tuple _ -> ()) cs
     | _ -> ());
    emit (["name",s t.Typedtree.typ_name.txt; "jkind",s (Format_doc.asprintf "%a" (Jkind.format Env.empty) t.typ_type.type_jkind);
      "written_jkind",(match t.typ_jkind_annotation with None -> `Null | Some j -> s (Format.asprintf "%a" Pprintast.jkind_annotation j))] @ basefields "typed_type_declaration" t.typ_loc);
    tbase.type_declaration self t);
  typ=(fun self ty ->
    (match ty.Typedtree.ctyp_desc with
    | Ttyp_arrow (_,arg,am,ret,rm) -> emit (["arg_locality",locality am.mode_modes; "ret_locality",locality rm.mode_modes; "arg_mode",const_mode am.mode_modes; "arg_written",mode_desc am.mode_desc;
        "ret_mode",const_mode rm.mode_modes; "ret_written",mode_desc rm.mode_desc;
        "argument_span",span arg.ctyp_loc; "return_span",span ret.ctyp_loc] @ basefields "typed_arrow" ty.ctyp_loc)
    | _ -> ()); tbase.typ self ty);
  value_binding=(fun self v ->
    let name = match v.Typedtree.vb_pat.pat_desc with Tpat_var {name=n; _} -> n.txt | _ -> "<pattern>" in
    with_owner name (fun () -> tbase.value_binding self v));
  expr=(fun self e ->
    List.iter (fun (extra,loc,_) -> match extra with
      | Typedtree.Texp_mode m -> emit (["written",mode_desc m.mode_desc] @ basefields "typed_expression_mode" loc)
      | _ -> ()) e.Typedtree.exp_extra;
    (match e.Typedtree.exp_desc with
    | Texp_function {params; _} -> List.iter (fun p ->
        let name = match p.Typedtree.fp_kind with
        | Tparam_pat {pat_desc=Tpat_var {name; _}; _}
        | Tparam_optional_default ({pat_desc=Tpat_var {name; _}; _},_,_) -> name.txt
        | _ -> "<pattern>" in
        emit (["name",s name; "mode",variable_mode p.Typedtree.fp_mode.mode_modes; "written",mode_desc p.fp_mode.mode_desc]
          @ basefields "typed_parameter" p.fp_loc)) params
    | _ -> ()); tbase.expr self e);
}
let read_source path =
  Lexer.handle_docstrings := true; Docstrings.init (); Lexer.init ();
  let ch = open_in path in let lb = Lexing.from_channel ch in Location.init lb path;
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    if Filename.check_suffix path ".mli" then piter.signature piter (Parse.interface lb)
    else piter.structure piter (Parse.implementation lb))
let read_typed path =
  let c = Cmt_format.read_cmt path in
  let resolved_source = Option.map (fun f -> if Sys.file_exists f then f else if Sys.file_exists (Filename.concat "_build/default" f) then Filename.concat "_build/default" f else Filename.concat c.cmt_builddir f) c.cmt_sourcefile in
  emit ["kind",s "artifact"; "input",s path; "source",(match c.cmt_sourcefile with None -> `Null | Some f -> s f);
    "builddir",s c.cmt_builddir; "resolved_source",(match resolved_source with None -> `Null | Some f -> s f);
    "digest_matches_source",(match resolved_source,c.cmt_source_digest with
      | Some f,Some d when Sys.file_exists f -> `Bool (Digest.file f = d) | _ -> `Null);
    "comments",i (List.length c.cmt_comments)];
  match c.cmt_annots with
  | Interface sg -> titer.signature titer sg
  | Implementation st -> titer.structure titer st
  | _ -> failwith "not a complete interface/implementation"
let () = for idx=1 to Array.length Sys.argv-1 do
  input := Sys.argv.(idx); owner := "";
  try if Filename.check_suffix !input ".mli" || Filename.check_suffix !input ".ml" then read_source !input
      else read_typed !input
  with ex -> Location.report_exception Format.err_formatter ex; exit 1
 done
