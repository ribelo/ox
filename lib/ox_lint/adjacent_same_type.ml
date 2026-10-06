(* ^safe-pwlt ^safe-k6aa ^safe-41f5: only sampled ordered endpoint roles. *)
open Ocaml_common
open Typedtree

let check ~(caps : < Ox_caps.Cap.fs_read ; .. >) ~emit ~undecided:_ =
  let base = Tast_iterator.default_iterator in
  let function_name = ref "" in
  let forwarders =
    List.filter_map
      (fun name ->
        try
          let _, d, _ =
            Env.lookup_value ~use:false ~loc:Location.none (Paths.lid name)
              (Lazy.force Env.initial)
          in
          Some d.Types.val_uid
        with Not_found | Env.Error _ -> None)
      [
        ("Unix", [ "rename" ]);
        ("Unix", [ "link" ]);
        ("Unix", [ "symlink" ]);
        ("Stdlib", [ "Sys"; "rename" ]);
        ("Ox_caps", [ "Cap_sys"; "rename" ]);
        ("Ox_caps", [ "Cap_unix"; "rename" ]);
        ("Ox_caps", [ "Cap_unix"; "link" ]);
        ("Ox_caps", [ "Cap_unix"; "symlink" ]);
      ]
  in
  let forwarding params body =
    match body with
    | Tfunction_body
        {
          exp_desc = Texp_apply ({ exp_desc = Texp_ident { desc; _ }; _ }, args, _, _, _);
          _;
        }
      when List.exists (Types.Uid.equal desc.val_uid) forwarders ->
        let inputs =
          List.filter_map
            (fun p ->
              match (p.fp_arg_label, p.fp_kind) with
              | Nolabel, Tparam_pat { pat_desc = Tpat_var { id; _ }; _ } -> Some id
              | _ -> None)
            params
        in
        let outputs =
          List.filter_map
            (function
              | Nolabel, Arg ({ exp_desc = Texp_ident { path = Path.Pident id; _ }; _ }, _)
                ->
                  Some id
              | Nolabel, _ -> None
              | _ -> None)
            args
        in
        List.length inputs = 2
        && List.length outputs = 2
        && List.for_all2 Ident.same inputs outputs
    | _ -> false
  in
  let parameter env p =
    match (p.fp_arg_label, p.fp_kind) with
    | Nolabel, Tparam_pat ({ pat_desc = Tpat_var { name; _ }; _ } as pat) -> (
        match Types.get_desc (Ctype.expand_head (Paths.env ~caps env) pat.pat_type) with
        | Tconstr (path, [], _)
          when List.exists (Path.same path)
                 [ Predef.path_int; Predef.path_float; Predef.path_string ] ->
            Some (name.txt, path, pat.pat_loc)
        | _ -> None)
    | _ -> None
  in
  let ordered left right =
    List.mem (left, right)
      [
        ("src", "dst");
        ("source", "destination");
        ("start", "stop");
        ("start", "end_");
        ("start_", "stop");
        ("start_", "end_");
        ("start_date", "end_date");
        ("start_pos", "end_pos");
        ("low", "high");
        ("index", "close");
        ("index", "text_start");
      ]
    || (!function_name = "compare_date" && left = "left" && right = "right")
  in
  {
    base with
    value_binding =
      (fun self binding ->
        let saved = !function_name in
        (match binding.vb_pat.pat_desc with
        | Tpat_var { name; _ } -> function_name := name.txt
        | _ -> ());
        base.value_binding self binding;
        function_name := saved);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_function { params; body; _ } when not (forwarding params body) ->
            let rec pairs = function
              | x :: (y :: _ as rest) ->
                  (match (parameter e.exp_env x, parameter e.exp_env y) with
                  | Some (left, a, loc), Some (right, b, _)
                    when Path.same a b && ordered left right ->
                      emit loc
                        ("ordered same-type endpoints " ^ left ^ "/" ^ right
                       ^ "; label their roles")
                  | _ -> ());
                  pairs rest
              | _ -> ()
            in
            pairs params
        | _ -> ());
        base.expr self e);
  }
