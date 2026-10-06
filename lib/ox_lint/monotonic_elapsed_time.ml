open Ocaml_common
open Typedtree

type wall_value = Wall | Opaque

let base = Tast_iterator.default_iterator

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

let check ~caps ~emit ~undecided =
  let roots names = Paths.values ~caps names in
  let wall =
    roots
      [
        ("Eio", [ "Time"; "now" ]);
        ("Unix", [ "gettimeofday" ]);
        ("Ox_caps", [ "Cap_unix"; "gettimeofday" ]);
      ]
  in
  let sleep =
    roots
      [
        ("Eio", [ "Time"; "sleep" ]);
        ("Eio", [ "Time"; "with_timeout" ]);
        ("Eio", [ "Time"; "Mono"; "sleep" ]);
      ]
  in
  let subtraction =
    roots [ ("Stdlib", [ "-." ]); ("Stdlib", [ "-" ]); ("Stdlib", [ "Int64"; "sub" ]) ]
  in
  let comparison =
    roots
      (List.map
         (fun name -> ("Stdlib", [ name ]))
         [ "<"; "<="; ">"; ">="; "="; "<>"; "compare" ]
      @ [
          ("Stdlib", [ "Float"; "compare" ]);
          ("Stdlib", [ "Int"; "compare" ]);
          ("Stdlib", [ "Int64"; "compare" ]);
        ])
  in
  let arithmetic =
    subtraction
    @ roots
        (List.map
           (fun name -> ("Stdlib", [ name ]))
           [
             "+.";
             "*.";
             "/.";
             "+";
             "*";
             "/";
             "~-";
             "~-.";
             "abs_float";
             "abs";
             "float_of_int";
             "int_of_float";
           ]
        @ [
            ("Stdlib", [ "Int64"; "of_float" ]);
            ("Stdlib", [ "Int64"; "to_float" ]);
            ("Stdlib", [ "Int64"; "of_int" ]);
            ("Stdlib", [ "Int64"; "to_int" ]);
            ("Stdlib", [ "Int64"; "add" ]);
            ("Stdlib", [ "Int64"; "mul" ]);
            ("Stdlib", [ "Int64"; "div" ]);
            ("Stdlib", [ "Int64"; "unsigned_div" ]);
          ])
  in
  let definitions = Path.Tbl.create 16 in
  let module_path = ref None in
  let collector =
    {
      base with
      module_binding =
        (fun self binding ->
          let saved = !module_path in
          module_path :=
            Option.map
              (fun id ->
                match saved with
                | None -> Path.Pident id
                | Some parent -> Path.Pdot (parent, Ident.name id))
              binding.mb_id;
          base.module_binding self binding;
          module_path := saved);
      structure_item =
        (fun self item ->
          (match (!module_path, item.str_desc) with
          | Some parent, Tstr_value (_, bindings) ->
              List.iter
                (fun binding ->
                  match binding.vb_pat.pat_desc with
                  | Tpat_var { id; _ } ->
                      Path.Tbl.replace definitions
                        (Path.Pdot (parent, Ident.name id))
                        binding.vb_expr
                  | _ -> ())
                bindings
          | _ -> ());
          base.structure_item self item);
      value_binding =
        (fun self binding ->
          (match binding.vb_pat.pat_desc with
          | Tpat_var { id; _ } ->
              Path.Tbl.replace definitions (Path.Pident id) binding.vb_expr
          | _ -> ());
          base.value_binding self binding);
    }
  in
  let rec resolve seen e =
    match e.exp_desc with
    | Texp_ident { path; _ } when not (List.exists (Path.same path) seen) -> (
        match Path.Tbl.find_opt definitions path with
        | Some next -> resolve (path :: seen) next
        | None -> e)
    | _ -> e
  in
  let is targets fn = Paths.is_value ~caps targets (resolve [] fn) in
  (* Only wall reads, local aliases, and expressions fed by them are relevant.
     Opaque calls are not sinks: uncertainty is reported only at a checked use. *)
  let join left right =
    match (left, right) with
    | Some Opaque, _ | _, Some Opaque -> Some Opaque
    | Some Wall, _ | _, Some Wall -> Some Wall
    | None, None -> None
  in
  let rec origin seen e =
    match e.exp_desc with
    | Texp_ident { path; _ } when not (List.exists (Path.same path) seen) ->
        Option.bind (Path.Tbl.find_opt definitions path) (origin (path :: seen))
    | Texp_apply (fn, _, _, _, _) when is wall fn -> Some Wall
    | Texp_apply (fn, args, _, _, _) when is subtraction fn -> (
        match arguments args with
        | [ (_, left); (_, right) ] -> (
            match (origin seen left, origin seen right) with
            | None, Some Wall -> None
            | left, right -> join left right)
        | _ -> None)
    | Texp_apply (fn, args, _, _, _) ->
        let inputs =
          List.fold_left
            (fun acc (_, value) -> join acc (origin seen value))
            None (arguments args)
        in
        if is arithmetic fn then inputs else Option.map (fun _ -> Opaque) inputs
    | Texp_let (_, _, body) | Texp_sequence (_, _, body) -> origin seen body
    | Texp_ifthenelse (_, yes, Some no) -> (
        match (origin seen yes, origin seen no) with
        | Some Wall, Some Wall -> Some Wall
        | None, None -> None
        | _ -> Some Opaque)
    | Texp_field { record; _ } -> Option.map (fun _ -> Opaque) (origin seen record)
    | Texp_tuple (values, _) ->
        List.fold_left (fun acc (_, value) -> join acc (origin seen value)) None values
    | Texp_construct (_, _, _, values, _) ->
        List.fold_left (fun acc (_, value) -> join acc (origin seen value)) None values
    | _ -> None
  in
  let numeric e =
    let env = Paths.env ~caps e.exp_env in
    match Types.get_desc (Ctype.expand_head env e.exp_type) with
    | Types.Tconstr (path, [], _) ->
        let path = Env.normalize_type_path None env path in
        List.exists (Path.same path)
          [ Predef.path_float; Predef.path_int; Predef.path_int64 ]
    | _ -> false
  in
  let finding loc =
    emit loc
      "wall-clock values must not measure elapsed time; use Eio.Time.Mono.now and \
       Mtime.span"
  in
  let opaque loc = undecided loc "opaque wall-clock value at elapsed-time use" in
  let initialized = ref false in
  {
    base with
    structure =
      (fun self tree ->
        if not !initialized then (
          initialized := true;
          collector.structure collector tree);
        base.structure self tree);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) -> (
            let args = arguments args in
            if is sleep fn then
              match List.filter (fun (label, _) -> label = Nolabel) args with
              | _ :: (_, delay) :: _ -> (
                  match origin [] delay with
                  | Some Wall -> finding e.exp_loc
                  | Some Opaque -> opaque e.exp_loc
                  | None -> ())
              | _ -> ()
            else if is subtraction fn || is comparison fn then
              match args with
              | [ (_, left); (_, right) ] when numeric left && numeric right -> (
                  match (origin [] left, origin [] right) with
                  | Some Wall, Some Wall -> finding e.exp_loc
                  | Some _, Some _ -> opaque e.exp_loc
                  | _ -> ())
              | _ -> ())
        | _ -> ());
        base.expr self e);
  }
