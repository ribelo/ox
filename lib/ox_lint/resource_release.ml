(* ^safe-cank ^safe-763t ^safe-mzdt: handle-specific local release evidence. *)
open Ocaml_common
open Typedtree

let check ~(caps : < Ox_caps.Cap.fs_read ; .. >) ~emit ~undecided =
  ignore caps#fs_read;
  let ids names =
    List.filter_map
      (fun name ->
        try
          let _, d, _ =
            Env.lookup_value ~use:false ~loc:Location.none (Paths.lid name)
              (Lazy.force Env.initial)
          in
          Some d.Types.val_uid
        with Not_found | Env.Error _ -> None)
      names
  in
  let unix names = ids (List.map (fun n -> ("Unix", [ n ])) names) in
  let acquire =
    ids
      (List.map
         (fun n -> ("Ox_caps", [ "Cap_unix"; n ]))
         [
           "openfile";
           "openfile_write";
           "open_process";
           "open_process_in";
           "open_process_out";
           "open_process_full";
           "open_process_args";
           "open_process_args_in";
           "open_process_args_out";
           "open_process_args_full";
           "socket";
           "pipe";
         ])
  in
  let close =
    unix
      [
        "close";
        "close_process";
        "close_process_in";
        "close_process_out";
        "close_process_full";
      ]
    @ ids
        [
          ("Stdlib", [ "close_in" ]);
          ("Stdlib", [ "close_out" ]);
          ("Stdlib", [ "close_in_noerr" ]);
          ("Stdlib", [ "close_out_noerr" ]);
          ("Eio", [ "Resource"; "close" ]);
        ]
  in
  let protect = ids [ ("Stdlib", [ "Fun"; "protect" ]) ] in
  let release = ids [ ("Eio", [ "Switch"; "on_release" ]) ] in
  let use = ids [ ("Ox", [ "Resource"; "use_in_scope" ]) ] in
  let use_closeable = ids [ ("Ox", [ "Resource"; "use_closeable_in_scope" ]) ] in
  let refs = ids [ ("Stdlib", [ "ref" ]); ("Stdlib", [ "!" ]) ] in
  let assign = ids [ ("Stdlib", [ ":=" ]) ] in
  let option_iter = ids [ ("Stdlib", [ "Option"; "iter" ]) ] in
  let aliases = ref [] and acquisitions = ref [] and sites = ref [] in
  let base = Tast_iterator.default_iterator in
  let args xs =
    List.filter_map (function l, Arg (e, _) -> Some (l, e) | _ -> None) xs
  in
  let positional xs = List.filter_map (function Nolabel, e -> Some e | _ -> None) xs in
  let rec resolve seen e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } when not (List.exists (Ident.same id) seen)
      -> (
        match List.find_opt (fun (other, _) -> Ident.same id other) !aliases with
        | Some (_, (target, _)) -> resolve (id :: seen) target
        | None -> e)
    | _ -> e
  in
  let known targets e =
    match (resolve [] e).exp_desc with
    | Texp_ident { desc; _ } -> List.exists (Types.Uid.equal desc.val_uid) targets
    | _ -> false
  in
  let rec bind pat source component =
    match pat.pat_desc with
    | Tpat_var { id; _ } -> aliases := (id, (source, component)) :: !aliases
    | Tpat_alias { id; pattern; _ } ->
        aliases := (id, (source, component)) :: !aliases;
        bind pattern source component
    | Tpat_tuple ps -> List.iteri (fun i (_, p) -> bind p source (Some i)) ps
    | Tpat_construct (_, _, _, [ (_, p) ], _) -> bind p source component
    | _ -> ()
  in
  let owner = ref [] in
  let gather =
    {
      base with
      value_binding =
        (fun self b ->
          bind b.vb_pat b.vb_expr None;
          base.value_binding self b);
      expr =
        (fun self e ->
          let saved = !owner in
          (match e.exp_desc with Texp_function _ -> owner := e :: saved | _ -> ());
          sites := (e, !owner) :: !sites;
          (match e.exp_desc with
          | Texp_apply (fn, _, _, _, _) when known acquire fn ->
              let count =
                match
                  Types.get_desc
                    (Ctype.expand_head (Paths.env ~caps e.exp_env) e.exp_type)
                with
                | Ttuple ts -> List.length ts
                | _ -> 1
              in
              acquisitions := (e, count, !owner) :: !acquisitions
          | Texp_match (source, _, cases, _, _) ->
              List.iter
                (fun c ->
                  match fst (Typedtree.split_pattern c.c_lhs) with
                  | Some p -> bind p source None
                  | None -> ())
                cases
          | Texp_apply (fn, xs, _, _, _) when known assign fn -> (
              match positional (args xs) with
              | [ { exp_desc = Texp_ident { path = Path.Pident id; _ }; _ }; value ] ->
                  aliases := (id, (value, None)) :: !aliases
              | _ -> ())
          | _ -> ());
          base.expr self e;
          owner := saved);
    }
  in
  let rec origins env seen component e =
    if List.exists (fun x -> x == e) seen then []
    else
      let seen = e :: seen in
      match List.find_opt (fun (source, _, _) -> source == e) !acquisitions with
      | Some (_, count, _) -> (
          match component with
          | Some i -> [ (e, i) ]
          | None -> List.init count (fun i -> (e, i)))
      | None -> (
          match e.exp_desc with
          | Texp_ident { path = Path.Pident id; _ } ->
              let entries =
                List.filter (fun (other, _) -> Ident.same id other) (env @ !aliases)
              in
              List.concat_map
                (fun (_, (target, index)) ->
                  origins env seen
                    (match component with Some _ -> component | None -> index)
                    target)
                entries
          | Texp_apply (fn, xs, _, _, _) when known refs fn ->
              List.concat_map (origins env seen component) (positional (args xs))
          | Texp_construct (_, _, _, [ (_, value) ], _) ->
              origins env seen component value
          | Texp_tuple (xs, _) ->
              List.concat_map (fun (_, x) -> origins env seen component x) xs
          | Texp_let (_, _, body) -> origins env seen component body
          | _ -> [])
  in
  let parameters params values =
    let _, env =
      List.fold_left
        (fun (remaining, env) p ->
          let rec take before = function
            | [] -> (None, remaining)
            | (label, value) :: rest when label = p.fp_arg_label ->
                (Some value, List.rev_append before rest)
            | x :: rest -> take (x :: before) rest
          in
          let value, remaining = take [] remaining in
          match (value, p.fp_kind) with
          | Some value, Tparam_pat { pat_desc = Tpat_var { id; _ }; _ } ->
              (remaining, (id, (value, None)) :: env)
          | _ -> (remaining, env))
        (values, []) params
    in
    env
  in
  let same (a, i) (b, j) = a == b && i = j in
  let rec closes env seen target e =
    let e = resolve [] e in
    if List.exists (fun other -> other == e) seen then false
    else
      let seen = e :: seen in
      let found = ref false in
      let visit =
        {
          base with
          expr =
            (fun self node ->
              (match node.exp_desc with
              | Texp_apply (fn, xs, _, _, _) -> (
                  let values = positional (args xs) in
                  if
                    known close fn
                    && List.exists
                         (fun v -> List.exists (same target) (origins env [] None v))
                         values
                  then found := true;
                  (if known option_iter fn then
                     match values with
                     | [ fn; value ]
                       when known close fn
                            && List.exists (same target) (origins env [] None value) ->
                         found := true
                     | _ -> ());
                  match (resolve [] fn).exp_desc with
                  | Texp_function { params; _ } ->
                      let supplied = parameters params (args xs) in
                      if closes (supplied @ env) seen target fn then found := true
                  | _ -> ())
              | _ -> ());
              base.expr self node);
        }
      in
      visit.expr visit e;
      !found
  in
  let exception_closes env target e =
    let found = ref false in
    let visit =
      {
        base with
        expr =
          (fun self e ->
            (match e.exp_desc with
            | Texp_try (_, handlers, _)
              when handlers <> []
                   && List.for_all (fun c -> closes env [] target c.c_rhs) handlers ->
                found := true
            | Texp_match (_, _, cases, _, _) ->
                let handlers =
                  List.filter
                    (fun c -> snd (Typedtree.split_pattern c.c_lhs) <> None)
                    cases
                in
                if
                  handlers <> []
                  && List.for_all (fun c -> closes env [] target c.c_rhs) handlers
                then found := true
            | _ -> ());
            base.expr self e);
      }
    in
    visit.expr visit e;
    !found
  in
  let related owners other =
    match (owners, other) with
    | [], [] -> true
    | _, x :: _ -> List.exists (fun owner -> owner == x) owners
    | _ -> false
  in
  let analysed = ref false in
  {
    base with
    structure =
      (fun _ tree ->
        if not !analysed then (
          analysed := true;
          gather.structure gather tree;
          List.iter
            (fun (source, count, owners) ->
              let protected component =
                List.exists
                  (fun (site, site_owners) ->
                    related owners site_owners
                    &&
                    match site.exp_desc with
                    | Texp_apply (fn, xs, _, _, _) -> (
                        let values = args xs in
                        if known protect fn then
                          match List.assoc_opt (Labelled "finally") values with
                          | Some callback -> closes [] [] (source, component) callback
                          | None -> false
                        else if known release fn then
                          List.exists
                            (closes [] [] (source, component))
                            (positional values)
                        else if known use fn || known use_closeable fn then
                          match positional values with
                          | producer :: callbacks ->
                              let found = ref false in
                              let v =
                                {
                                  base with
                                  expr =
                                    (fun self e ->
                                      if e == source then found := true;
                                      base.expr self e);
                                }
                              in
                              v.expr v (resolve [] producer);
                              let result =
                                match (resolve [] producer).exp_desc with
                                | Texp_function { body = Tfunction_body result; _ } ->
                                    result
                                | _ -> resolve [] producer
                              in
                              let returned =
                                List.exists
                                  (fun (origin, part) ->
                                    origin == source && part = component)
                                  (origins [] [] None result)
                              in
                              !found
                              &&
                              if known use_closeable fn then
                                closes [] [] (source, component) producer
                              else
                                returned
                                && List.exists
                                     (fun callback ->
                                       if known close callback then true
                                       else
                                         match (resolve [] callback).exp_desc with
                                         | Texp_function { params; _ } ->
                                             closes
                                               (parameters params [ (Nolabel, source) ])
                                               [] (source, component) callback
                                         | _ -> false)
                                     callbacks
                          | _ -> false
                        else
                          match (resolve [] fn).exp_desc with
                          | Texp_function { params; _ } ->
                              exception_closes (parameters params values)
                                (source, component) (resolve [] fn)
                          | _ -> false)
                    | Texp_try (_, handlers, _) ->
                        handlers <> []
                        && List.for_all
                             (fun c -> closes [] [] (source, component) c.c_rhs)
                             handlers
                        && List.exists
                             (fun (e, o) ->
                               related owners o && closes [] [] (source, component) e)
                             !sites
                    | Texp_match (_, _, cases, _, _) ->
                        let exceptions =
                          List.filter
                            (fun c -> snd (Typedtree.split_pattern c.c_lhs) <> None)
                            cases
                        in
                        exceptions <> []
                        && List.for_all
                             (fun c -> closes [] [] (source, component) c.c_rhs)
                             exceptions
                    | _ -> false)
                  !sites
              in
              if not (List.for_all protected (List.init count Fun.id)) then
                emit source.exp_loc
                  "acquired handle has no local structured or proven exceptional release \
                   path; establish cleanup before use")
            (List.rev !acquisitions);
          ignore undecided));
  }
