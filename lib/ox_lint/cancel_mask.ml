(* ^safe-ctc4 ^safe-vj9b ^safe-tcqo: concrete shielded Eio nontermination. *)
open Ocaml_common
open Typedtree

let rec type_path_matches fuel expected ty =
  if fuel = 0 then false
  else
    match Types.get_desc ty with
    | Tlink body | Tpoly (body, _) -> type_path_matches (fuel - 1) expected body
    | Tconstr (path, _, _) -> Path.same path expected
    | _ -> false

let base = Tast_iterator.default_iterator

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

let check ~caps ~emit ~undecided =
  let values names =
    Paths.values ~caps
      (List.map (function first :: rest -> (first, rest) | [] -> assert false) names)
  in
  let masks =
    values
      [
        [ "Eio"; "Cancel"; "protect" ];
        [ "Eio"; "Switch"; "run_protected" ];
        [ "Eio"; "Switch"; "on_release" ];
        [ "Eio"; "Switch"; "on_release_cancellable" ];
      ]
  in
  let mutex = values [ [ "Eio"; "Mutex"; "use_rw" ] ] in
  let indefinite = values [ [ "Eio"; "Fiber"; "await_cancel" ] ] in
  let server = values [ [ "Eio"; "Net"; "run_server" ] ] in
  let timeout =
    values [ [ "Eio"; "Time"; "with_timeout" ]; [ "Eio"; "Time"; "with_timeout_exn" ] ]
  in
  let timeout_run =
    values
      [ [ "Eio"; "Time"; "Timeout"; "run" ]; [ "Eio"; "Time"; "Timeout"; "run_exn" ] ]
  in
  let seconds = values [ [ "Eio"; "Time"; "Timeout"; "seconds" ] ] in
  let none = values [ [ "Eio"; "Time"; "Timeout"; "none" ] ] in
  let runners = values [ [ "Eio"; "Switch"; "run" ]; [ "Eio_main"; "run" ] ] in
  let forks =
    values
      [
        [ "Eio"; "Fiber"; "fork" ];
        [ "Eio"; "Fiber"; "fork_daemon" ];
        [ "Eio"; "Fiber"; "fork_promise" ];
      ]
  in
  let finally = values [ [ "Stdlib"; "Fun"; "protect" ]; [ "Fun"; "protect" ] ] in
  let bindings = Path.Tbl.create 32 and reported = Hashtbl.create 8 in
  let report category callback loc message =
    let key = (category, loc.Location.loc_start, loc.Location.loc_end, message) in
    if not (Hashtbl.mem reported key) then (
      Hashtbl.add reported key ();
      callback loc message)
  in
  let rec resolve env depth e =
    if depth = 0 then e
    else
      match e.exp_desc with
      | Texp_ident { path; _ } -> (
          let replacement =
            match List.find_opt (fun (p, _) -> Path.same path p) env with
            | Some (_, value) -> Some value
            | None -> Path.Tbl.find_opt bindings path
          in
          match replacement with
          | Some value when value != e -> resolve env (depth - 1) value
          | _ -> e)
      | _ -> e
  in
  let is env paths e =
    let e = resolve env 32 e in
    if not (Paths.is_value ~caps paths e) then false
    else
      match e.exp_desc with
      | Texp_ident { path; desc; _ } ->
          let authentic = Env.find_value path (Paths.env ~caps e.exp_env) in
          if Types.Uid.equal desc.val_uid authentic.val_uid then true
          else (
            report "unknown" undecided e.exp_loc
              "unverified cancellation-mask evidence: compiler value UID disagrees with \
               resolved environment";
            false)
      | _ -> false
  in
  let bind env binding =
    match binding.vb_pat.pat_desc with
    | Tpat_var { id; _ } -> (Path.Pident id, resolve env 32 binding.vb_expr) :: env
    | _ -> env
  in
  let bool env e =
    let e = resolve env 32 e in
    match e.exp_desc with
    | Texp_construct (_, d, _, _, _)
      when d.cstr_name = "true" && type_path_matches 32 Predef.path_bool e.exp_type ->
        Some true
    | Texp_construct (_, d, _, _, _)
      when d.cstr_name = "false" && type_path_matches 32 Predef.path_bool e.exp_type ->
        Some false
    | _ -> None
  in
  let callback args =
    List.find_opt (fun (label, _) -> label = Nolabel) (List.rev args) |> Option.map snd
  in
  let duration env e =
    match (resolve env 32 e).exp_desc with
    | Texp_constant (Const_float value) ->
        let n = float_of_string value in
        Float.is_finite n && n < 9223372036854775808. /. 1e9
    | _ -> false
  in
  let indefinite_wait masked deadline loc =
    if masked then
      match deadline with
      | Some false ->
          report "finding" emit loc
            "known indefinite server/cancellation wait executes inside cancellation \
             protection; reduce mask scope or use an inner finite deadline"
      | None ->
          report "unknown" undecided loc
            "unresolved protection/deadline around a known indefinite cancellation wait"
      | Some true -> ()
  in
  let saturated env fn args =
    let fn = resolve env 32 fn in
    let rec labels fuel ty =
      if fuel = 0 then []
      else
        match Types.get_desc ty with
        | Tarrow ((label, _, _), _, rest, _) -> (
            let tail = labels (fuel - 1) rest in
            match label with Optional _ -> tail | _ -> label :: tail)
        | Tpoly (body, _) | Tlink body -> labels (fuel - 1) body
        | _ -> []
    in
    let rec supplied args = function
      | [] -> true
      | label :: rest -> (
          let rec take prefix = function
            | [] -> None
            | (l, _) :: tail when l = label -> Some (List.rev_append prefix tail)
            | arg :: tail -> take (arg :: prefix) tail
          in
          match take [] args with Some args -> supplied args rest | None -> false)
    in
    match fn.exp_desc with
    | Texp_ident { desc; _ } -> supplied args (labels 32 desc.val_type)
    | _ -> false
  in
  let contains_wait env expression =
    let found = ref false in
    let rec scan depth e =
      if depth > 0 && not !found then
        let e = resolve env 32 e in
        if is env indefinite e then found := true
        else
          match e.exp_desc with
          | Texp_apply (fn, raw, _, _, _)
            when is env server fn && saturated env fn (arguments raw) ->
              found := true
          | _ -> base.expr { base with expr = (fun _ child -> scan (depth - 1) child) } e
    in
    scan 32 expression;
    !found
  in
  let rec invoke ?(implicit = 1) masked deadline env active fuel fn args =
    let closure = resolve env 32 fn in
    if fuel > 0 && not (List.exists (( == ) closure) active) then
      match closure.exp_desc with
      | Texp_function { params; body; _ } ->
          let rec parameters env implicit params args =
            match (params, args) with
            | [], [] -> Some env
            | [], _ :: _ -> None
            | param :: rest, arg :: args ->
                let env =
                  match param.fp_kind with
                  | Tparam_pat { pat_desc = Tpat_var { id; _ }; _ } ->
                      (Path.Pident id, resolve env 32 arg) :: env
                  | _ -> env
                in
                parameters env implicit rest args
            | _ :: rest, [] when implicit > 0 -> parameters env (implicit - 1) rest []
            | _ -> None
          in
          Option.iter
            (fun env ->
              let visit = execute masked deadline env (closure :: active) (fuel - 1) in
              match body with
              | Tfunction_body body -> visit body
              | Tfunction_cases cases ->
                  List.iter
                    (fun case ->
                      Option.iter visit case.c_guard;
                      visit case.c_rhs)
                    cases.fc_cases)
            (parameters env implicit params args)
      | _ when is env indefinite closure ->
          indefinite_wait masked deadline closure.exp_loc
      | _ -> ()
    else if masked && contains_wait env closure then
      report "unknown" undecided closure.exp_loc
        "cancellation-mask local invocation horizon or recursive known-wait callback"
  and execute masked deadline env active fuel e =
    let visit = execute masked deadline env active fuel in
    let walker = { base with expr = (fun _ child -> visit child) } in
    match e.exp_desc with
    | Texp_function _ | Texp_lazy _ -> ()
    | Texp_let (_, bindings, body) ->
        List.iter (fun b -> visit b.vb_expr) bindings;
        execute masked deadline (List.fold_left bind env bindings) active fuel body
    | Texp_ifthenelse (condition, yes, no) -> (
        visit condition;
        match bool env condition with
        | Some true -> visit yes
        | Some false -> Option.iter visit no
        | None ->
            visit yes;
            Option.iter visit no)
    | Texp_apply (fn, raw, _, _, _) ->
        let args = arguments raw in
        List.iter (fun (_, arg) -> visit arg) args;
        let call masked deadline =
          Option.iter
            (fun body -> invoke masked deadline env active fuel body [])
            (callback args)
        in
        if is env masks fn then call true (Some false)
        else if is env mutex fn then
          match Option.bind (List.assoc_opt (Labelled "protect") args) (bool env) with
          | Some true -> call true (Some false)
          | Some false -> call masked deadline
          | None -> call true None
        else if is env runners fn then call masked deadline
        else if is env forks fn then
          if
            masked
            &&
            match callback args with
            | Some body -> contains_wait env body
            | None -> false
          then
            report "unknown" undecided e.exp_loc
              "forked known-wait callback cancellation context depends on its switch; no \
               shield inheritance is certified"
          else call false (Some false)
        else if is env indefinite fn then indefinite_wait masked deadline e.exp_loc
        else if is env server fn && saturated env fn args then (
          Option.iter
            (fun body -> invoke ~implicit:2 false (Some false) env active fuel body [])
            (callback args);
          let stopping =
            match List.assoc_opt (Optional "stop") args with
            | None -> Some false
            | Some stop -> (
                let stop = resolve env 32 stop in
                let canonical = type_path_matches 32 Predef.path_option stop.exp_type in
                match stop.exp_desc with
                | Texp_construct (_, d, _, [], _) when canonical && d.cstr_name = "None"
                  ->
                    Some false
                | Texp_construct (_, d, _, [ _ ], _)
                  when canonical && d.cstr_name = "Some" ->
                    Some true
                | _ -> None)
          in
          if masked && deadline <> Some true && stopping <> Some true then
            if deadline = None || stopping = None then
              report "unknown" undecided e.exp_loc
                "unresolved stop/deadline around a protected server wait"
            else if deadline = Some false then
              report "finding" emit e.exp_loc
                "known indefinite server wait executes inside cancellation protection; \
                 reduce mask scope or change the interface")
        else if is env timeout fn then
          let positional = List.filter (fun (label, _) -> label = Nolabel) args in
          let finite =
            match positional with
            | _ :: (_, bound) :: _ -> duration env bound
            | _ -> false
          in
          call masked (if finite || deadline = Some true then Some true else None)
        else if is env timeout_run fn then
          let bound =
            match args with
            | (_, token) :: _ -> (
                let token = resolve env 32 token in
                if is env none token then Some false
                else
                  match token.exp_desc with
                  | Texp_apply (constructor, raw, _, _, _) when is env seconds constructor
                    -> (
                      match callback (arguments raw) with
                      | Some n when duration env n -> Some true
                      | _ -> None)
                  | _ -> None)
            | _ -> None
          in
          call masked
            (if bound = Some true || deadline = Some true then Some true
             else if bound = Some false then deadline
             else None)
        else if is env finally fn then (
          call masked deadline;
          Option.iter
            (fun body -> invoke masked deadline env active fuel body [])
            (List.assoc_opt (Labelled "finally") args))
        else invoke ~implicit:0 masked deadline env active fuel fn (List.map snd args)
    | _ -> base.expr walker e
  in
  let root e =
    match e.exp_desc with
    | Texp_function { body = Tfunction_body body; _ } ->
        execute false (Some false) [] [] 128 body
    | Texp_function { body = Tfunction_cases cases; _ } ->
        List.iter
          (fun case -> execute false (Some false) [] [] 128 case.c_rhs)
          cases.fc_cases
    | _ -> execute false (Some false) [] [] 128 e
  in
  {
    base with
    value_binding =
      (fun self binding ->
        (match binding.vb_pat.pat_desc with
        | Tpat_var { id; _ } -> Path.Tbl.replace bindings (Path.Pident id) binding.vb_expr
        | _ -> ());
        base.value_binding self binding);
    structure_item =
      (fun self item ->
        base.structure_item self item;
        match item.str_desc with
        | Tstr_value (_, values) -> List.iter (fun value -> root value.vb_expr) values
        | Tstr_eval (e, _, _) -> root e
        | _ -> ());
  }
