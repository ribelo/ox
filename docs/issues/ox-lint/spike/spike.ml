(* Throwaway typed-tier probe; compiled by the same OxCaml as its inputs. *)
open Typedtree
let files = ref []
let sites = ref false
let paths = ref false
let has_eio = ref false
let raw = ref false
let allow_stale = ref false
let build_root = ref "_build/default"
let failures = ref 0
let findings = ref 0
let candidates = ref 0
let expressions = ref 0
let result_expressions = ref 0
let implementations = ref 0
let file = ref ""
let lid names = Option.get (Longident.unflatten names)
let loc loc = Printf.sprintf "%s:%d:%d" loc.Location.loc_start.Lexing.pos_fname
  loc.loc_start.pos_lnum (loc.loc_start.pos_cnum - loc.loc_start.pos_bol)
let basename p = Path.last p
let env e = Envaux.env_of_only_summary ~allow_missing_modules:false e
let norm_value e p = Env.normalize_value_path None (env e) p
(* Canonical targets use the initial environment, never the lexical environment:
   a local module named Stdlib must not redefine what "really result" means. *)
let canonical_value _ names =
  let e = Lazy.force Env.initial in let p, _, _ = Env.lookup_value ~use:false ~loc:Location.none (lid names) e in
  Env.normalize_value_path None e p
let canonical_result _ =
  let e = Lazy.force Env.initial in let p, _ = Env.lookup_type ~use:false ~loc:Location.none (lid ["Stdlib"; "result"]) e in
  Env.normalize_type_path None e p
let canonical_cancelled () =
  let e = Lazy.force Env.initial in
  fst (Env.lookup_constructor ~use:false ~loc:Location.none Env.Pattern (lid ["Eio"; "Cancel"; "Cancelled"]) e)
let is_result e =
  let en = env e.exp_env in
  let typ = Ctype.expand_head en e.exp_type in
  match Types.get_desc typ with
  | Tconstr (p, [_; _], _) -> Path.same (Env.normalize_type_path None en p) (canonical_result en)
  | _ -> false
let pp_type e = Format.asprintf "%a" Printtyp.type_expr e.exp_type
let head e = match Types.get_desc e.exp_type with Tconstr (p, _, _) -> Path.name p | _ -> "<not-constructor>"
let report kind place e =
  incr candidates;
  let result = is_result e in
  if !sites then Printf.printf "SITE\t%s\t%s\t%b\t%s\t%s\n" (loc place) kind result (head e) (pp_type e);
  if result then begin incr findings;
    Printf.printf "%s: ox-lint-discard-result: %s discards %s; match Ok/Error or propagate the error\n" (loc place) kind (pp_type e)
  end
let rebindings = Path.Tbl.create 8
let rec extension_origin env path =
  match Path.Tbl.find_opt rebindings path with
  | Some origin -> extension_origin env origin
  | None -> norm_value env path
let base = Tast_iterator.default_iterator
let iterator = { base with
  extension_constructor = (fun self ext ->
    (match ext.ext_kind with
    | Text_rebind (path, _) ->
        Path.Tbl.replace rebindings (Path.Pident ext.ext_id) path;
        if !paths then Printf.printf "REBIND\t%s\t%s\t%s\n"
        (loc ext.ext_loc) ext.ext_name.txt (Path.name (norm_value (Lazy.force Env.initial) path))
    | _ -> ()); base.extension_constructor self ext);
  expr = (fun self e ->
    incr expressions;
    if is_result e then incr result_expressions;
    (match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) ->
        (match fn.exp_desc with
        | Texp_ident {path; _} when Path.same (norm_value fn.exp_env path) (canonical_value fn.exp_env ["Stdlib"; "ignore"]) ->
            List.iter (function _, Arg (arg, _) -> report "ignore" e.exp_loc arg | _ -> ()) args
        | _ -> ())
    | Texp_ident {path; lid; _} when !paths ->
        let n = Path.last path in
        if List.mem n ["fork"; "ignore"; "cancelled"] then
          Printf.printf "IDENT\t%s\t%s\t%s\t%s\teio_fork=%b\n" (loc e.exp_loc) (Format.asprintf "%a" Printtyp.longident lid.txt)
            (Path.name path) (Path.name (norm_value e.exp_env path))
            (n = "fork" && !has_eio && Path.same (norm_value e.exp_env path) (canonical_value e.exp_env ["Eio"; "Fiber"; "fork"]))
    | _ -> ());
    base.expr self e);
  value_binding = (fun self vb ->
    (match vb.vb_pat.pat_desc with Tpat_any -> report "let _ =" vb.vb_pat.pat_loc vb.vb_expr | _ -> ());
    base.value_binding self vb);
  pat = (fun (type k) self (p : k general_pattern) ->
    (match p.pat_desc with
    | Tpat_construct (name, desc, _, _, _) when !paths ->
        (match desc.cstr_tag with
        | Types.Extension path ->
            let target = if !has_eio then Some (canonical_cancelled ()) else None in
            let same_path = match Option.map (fun d -> d.Data_types.cstr_tag) target with
              | Some (Types.Extension tp) -> Path.same (extension_origin p.pat_env path) (norm_value p.pat_env tp)
              | _ -> false in
            Printf.printf "EXCEPTION\t%s\t%s\t%s\t%s\tcancel_path=%b\tcancel_uid=%b\n" (loc p.pat_loc)
              (Format.asprintf "%a" Printtyp.longident name.txt) (Path.name path) (Path.name (norm_value p.pat_env path))
              same_path (Option.fold ~none:false ~some:(fun d -> Types.Uid.equal desc.cstr_uid d.Data_types.cstr_uid) target)
        | _ -> ())
    | _ -> ());
    base.pat self p);
}
let absolute p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p
let setup c =
  Path.Tbl.clear rebindings;
  Envaux.reset_cache ~preserve_persistent_env:false;
  let rebase p = if Filename.is_relative p then Filename.concat (absolute !build_root) p else p in
  Load_path.init ~auto_include:Load_path.no_auto_include
    ~visible:(List.map (fun (p : Clflags.visible_include) -> {p with path = rebase p.path}) c.Cmt_format.cmt_loadpath.visible)
    ~hidden:(List.map rebase c.cmt_loadpath.hidden);
  has_eio := (try ignore (Load_path.find "eio.cmi"); true with Not_found -> false)
let source_path name =
  if Sys.file_exists name then name
  else let p = Filename.concat !build_root name in if Sys.file_exists p then p else name
let fresh c =
  match c.Cmt_format.cmt_sourcefile, c.cmt_source_digest with
  | Some name, Some digest ->
      let p = source_path name in
      if not (Sys.file_exists p) then failwith ("source not found: " ^ p);
      if Digest.file p <> digest then failwith ("stale cmt: source digest mismatch: " ^ p)
  | _ -> failwith "source digest unavailable"
let read name =
  file := name;
  try
    let c = Cmt_format.read_cmt name in
    if not !allow_stale then fresh c;
    match c.cmt_annots with
    | Implementation t ->
        incr implementations;
        if not !raw then setup c;
        if !raw then begin
          let it = { base with expr = (fun self e -> incr expressions; base.expr self e) } in
          it.structure it t
        end else iterator.structure iterator t
    | _ -> failwith "not a complete Implementation"
  with ex -> incr failures; Printf.eprintf "FAIL\t%s\t%s\n" name (Printexc.to_string ex)
let () =
  Arg.parse ["--sites", Arg.Set sites, "Print all syntactic discard candidates";
    "--paths", Arg.Set paths, "Print selected resolved identifiers and exception patterns";
    "--raw", Arg.Set raw, "Read/traverse without environment reconstruction";
    "--allow-stale", Arg.Set allow_stale, "For evidence only: omit source digest check";
    "--build-root", Arg.Set_string build_root, "DIR: rebase dune relative load paths"]
    (fun name -> files := name :: !files) "spike [OPTIONS] CMT...";
  List.iter read (List.rev !files);
  Printf.eprintf "SUMMARY implementations=%d expressions=%d result_expressions=%d candidates=%d findings=%d failures=%d\n"
    !implementations !expressions !result_expressions !candidates !findings !failures;
  exit (if !failures > 0 then 2 else if !findings > 0 then 1 else 0)
