(* ^safe-8pmk ^safe-p1m1 ^safe-iq5u: a bounded construction rule, not SQL validation. *)
open Ocaml_common
open Typedtree

type text = Literal | Other | Dynamic
type actual = { value : expression; captured : (Path.t * actual) list }

let message =
  "unparameterized dynamic SQL construction reaches a raw execution sink; bind values \
   separately (not proof of injection)"

let check ~(caps : < Ox_caps.Cap.fs_read ; .. >) ~emit ~undecided =
  (* Look up genuine value UIDs in the initial compiler environment, not lexical
     spellings or a reconstructed environment from an imported expression. *)
  let identities names =
    ignore caps#fs_read;
    List.filter_map
      (fun name ->
        try
          let _, value, _ =
            Env.lookup_value ~use:false ~loc:Location.none (Paths.lid name)
              (Lazy.force Env.initial)
          in
          Some value.val_uid
        with Not_found | Env.Error _ -> None)
      names
  in
  let std name = identities [ ("Stdlib", name) ] in
  let concat = std [ "^" ] in
  let join = std [ "String"; "concat" ] in
  let format = std [ "Printf"; "sprintf" ] @ std [ "Format"; "asprintf" ] in
  let buffer_create = std [ "Buffer"; "create" ] in
  let buffer_contents = std [ "Buffer"; "contents" ] in
  let buffer_add = std [ "Buffer"; "add_string" ] @ std [ "Buffer"; "add_char" ] in
  let buffer_reset = std [ "Buffer"; "clear" ] @ std [ "Buffer"; "reset" ] in
  let sinks =
    identities
      ([ ("Sqlite3", [ "exec" ]); ("Sqlite3", [ "prepare" ]) ]
      @ List.map
          (fun name -> ("Ox_sql", [ "Pool"; "Raw"; name ]))
          [ "query"; "fold"; "execute"; "execute_script" ]
      @ List.map
          (fun name -> ("Ox_sql", [ "Sqlite"; name ]))
          [
            "prepare";
            "prepare_owned";
            "prepare_result";
            "prepare_owned_result";
            "exec";
            "exec_result";
            "exec_script";
            "exec_script_result";
            "query_one_int";
            "query_one_int_result";
          ]
      @ List.map
          (fun name -> ("Ox_sql__Connection", [ name ]))
          [ "prepare"; "query"; "query_one"; "execute"; "execute_script" ])
  in
  let bindings = Path.Tbl.create 32 in
  let owners = Hashtbl.create 32 in
  let mutations = ref [] in
  let reported = Hashtbl.create 16 in
  let base = Tast_iterator.default_iterator in
  let args arguments =
    List.filter_map
      (function label, Arg (e, _) -> Some (label, e) | _ -> None)
      arguments
  in
  let bind table pattern expression =
    match pattern.pat_desc with
    | Tpat_var { id; _ } -> Path.Tbl.replace table (Path.Pident id) expression
    | _ -> ()
  in
  (* Each substituted actual keeps its caller environment. Reusing a helper's
     formal identifiers cannot overwrite captures or previous actuals. *)
  let exhausted = ref false in
  let rec origin budget substitutions e =
    if budget = 0 then (
      exhausted := true;
      (substitutions, e))
    else
      match e.exp_desc with
      | Texp_ident { path; _ } -> (
          match List.find_opt (fun (p, _) -> Path.same p path) substitutions with
          | Some (_, actual) -> origin (budget - 1) actual.captured actual.value
          | None -> (
              match Path.Tbl.find_opt bindings path with
              | Some bound -> origin (budget - 1) substitutions bound
              | None -> (substitutions, e)))
      | _ -> (substitutions, e)
  and application budget substitutions fn arguments =
    let substitutions, fn = origin budget substitutions fn in
    match fn.exp_desc with
    | Texp_apply (parent, prefix, _, _, _) when budget > 0 ->
        application (budget - 1) substitutions parent (args prefix @ arguments)
    | _ -> (substitutions, fn, arguments)
  in
  let is identities fn =
    match fn.exp_desc with
    | Texp_ident { desc; _ } -> List.exists (Types.Uid.equal desc.val_uid) identities
    | _ -> false
  in
  let transfer substitutions fn actuals =
    match fn.exp_desc with
    | Texp_function { params; body = Tfunction_body body; _ }
      when List.length params = List.length actuals ->
        let rec parameters accumulated params actuals =
          match (params, actuals) with
          | [], [] -> Some (accumulated, body)
          | param :: rest, (label, actual) :: tail when label = param.fp_arg_label -> (
              match param.fp_kind with
              | Tparam_pat { pat_desc = Tpat_var { id; _ }; _ } ->
                  parameters
                    ((Path.Pident id, { value = actual; captured = substitutions })
                    :: accumulated)
                    rest tail
              | Tparam_pat { pat_desc = Tpat_any; _ } -> parameters accumulated rest tail
              | _ -> None)
          | _ -> None
        in
        parameters substitutions params actuals
    | _ -> None
  in
  let combine items = if List.for_all (( = ) Literal) items then Literal else Dynamic in
  let source_fuel = ref 256 in
  let rec text budget substitutions expression =
    if budget = 0 || !source_fuel = 0 then (
      exhausted := true;
      Other)
    else (
      decr source_fuel;
      let substitutions, e = origin 32 substitutions expression in
      let next = text (budget - 1) substitutions in
      match e.exp_desc with
      | Texp_constant _ -> Literal
      | Texp_construct (_, _, _, children, _) ->
          if List.for_all (fun (_, child) -> next child = Literal) children then Literal
          else Other
      | Texp_let (_, _, body) | Texp_sequence (_, _, body) -> next body
      | Texp_ifthenelse (_, yes, Some no) -> (
          match (next yes, next no) with
          | Literal, Literal -> Literal
          | Dynamic, _ | _, Dynamic -> Dynamic
          | _ -> Other)
      | Texp_apply (fn, arguments, _, _, _) -> (
          let scope, fn, actuals = application 32 substitutions fn (args arguments) in
          let values = List.map snd actuals in
          let classify = text (budget - 1) scope in
          if is concat fn || is join fn then combine (List.map classify values)
          else if is format fn then
            match values with
            | { exp_desc = Texp_construct (_, _, _, [ _; (_, literal) ], _); _ } :: values
              ->
                combine (classify literal :: List.map classify values)
            | _ -> combine (List.map classify values)
          else if is buffer_contents fn then buffer_text budget scope e values
          else
            match transfer scope fn actuals with
            | Some (scope, body) -> text (budget - 1) scope body
            | None -> Other)
      | _ -> Other)
  and buffer_text budget substitutions contents = function
    | [ buffer ] -> (
        let _, allocation = origin 32 substitutions buffer in
        match allocation.exp_desc with
        | Texp_apply (fn, _, _, _, _) when is buffer_create fn ->
            let owner = Hashtbl.find_opt owners contents.exp_loc in
            let before = contents.exp_loc.loc_start.pos_cnum in
            let events =
              List.filter_map
                (fun (target, event_owner, loc, added) ->
                  let _, target = origin 32 substitutions target in
                  if
                    target == allocation && event_owner = owner
                    && loc.Location.loc_start.pos_cnum < before
                  then Some added
                  else None)
                !mutations
            in
            (* Clearing or resetting invalidates this small append-only proof. *)
            if List.exists Option.is_none events then Other
            else
              combine
                (List.filter_map (Option.map (text (budget - 1) substitutions)) events)
        | _ -> Other)
    | _ -> Other
  in
  let owner = ref None in
  let collect =
    {
      base with
      value_binding =
        (fun self binding ->
          bind bindings binding.vb_pat binding.vb_expr;
          base.value_binding self binding);
      expr =
        (fun self e ->
          Hashtbl.replace owners e.exp_loc !owner;
          (match e.exp_desc with
          | Texp_apply (fn, arguments, _, _, _) -> (
              let _, fn, actuals = application 32 [] fn (args arguments) in
              match List.map snd actuals with
              | [ buffer; content ] when is buffer_add fn ->
                  mutations :=
                    (buffer, Some !owner, e.exp_loc, Some content) :: !mutations
              | [ buffer ] when is buffer_reset fn ->
                  mutations := (buffer, Some !owner, e.exp_loc, None) :: !mutations
              | values when not (is buffer_create fn || is buffer_contents fn) ->
                  List.iter
                    (fun target ->
                      let _, allocation = origin 32 [] target in
                      match allocation.exp_desc with
                      | Texp_apply (create, _, _, _, _) when is buffer_create create ->
                          mutations :=
                            (target, Some !owner, e.exp_loc, None) :: !mutations
                      | _ -> ())
                    values
              | _ -> ())
          | _ -> ());
          let saved = !owner in
          (match e.exp_desc with Texp_function _ -> owner := Some e.exp_loc | _ -> ());
          base.expr self e;
          owner := saved);
    }
  in
  let report loc =
    if not (Hashtbl.mem reported loc) then (
      Hashtbl.add reported loc ();
      emit loc message)
  in
  let call_fuel = ref 512 in
  let rec inspect budget substitutions e =
    if budget > 0 && !call_fuel > 0 then (
      decr call_fuel;
      match e.exp_desc with
      | Texp_apply (fn, arguments, _, _, _) -> (
          let scope, fn, actuals = application 32 substitutions fn (args arguments) in
          let positional =
            List.filter_map
              (fun (label, e) -> if label = Nolabel then Some e else None)
              actuals
          in
          (match positional with
          | _db :: sql :: _ when is sinks fn ->
              source_fuel := 256;
              exhausted := false;
              let source = text 64 scope sql in
              if !exhausted then
                undecided sql.exp_loc
                  "raw SQL source/alias horizon exhausted at a known sink"
              else if source = Dynamic then report sql.exp_loc
          | _ -> ());
          match transfer scope fn actuals with
          | Some (scope, body) -> walk (budget - 1) scope body
          | None -> ())
      | _ -> ())
  and walk budget substitutions body =
    let visitor =
      {
        base with
        expr =
          (fun self e ->
            inspect budget substitutions e;
            match e.exp_desc with Texp_function _ -> () | _ -> base.expr self e);
      }
    in
    visitor.expr visitor body
  in
  {
    base with
    structure =
      (fun self tree ->
        collect.structure collect tree;
        base.structure self tree);
    expr =
      (fun self e ->
        call_fuel := 512;
        inspect 8 [] e;
        base.expr self e);
  }
