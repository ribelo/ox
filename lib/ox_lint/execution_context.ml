(* ^safe-sr6e ^safe-9hbm ^safe-eftp: known execution-context candidates, not NoEio certification. *)
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

type role = Worker | Eio | Root | Wait | Pure | Callback
type context = Outside | Owner | Native of string * Location.t

type head = {
  path : Path.t;
  uid : Shape.Uid.t;
  name : string;
  labels : arg_label list;
  role : role;
}

type value =
  | Head of head * (arg_label * value) list
  | Closure of expression * environment * (arg_label * value) list
  | Group of value list
  | Boolean of bool
  | Optional_value of value option

and environment = (Path.t * value) list

let check ~caps ~emit ~undecided =
  let initial = Lazy.force Env.initial in
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
  let catalogue role names =
    List.filter_map
      (fun names ->
        match names with
        | [] -> None
        | first :: rest -> (
            try
              let path, desc, _ =
                Env.lookup_value ~use:false ~loc:Location.none
                  (Paths.lid (first, rest))
                  initial
              in
              Some
                {
                  path = Env.normalize_value_path None initial path;
                  uid = desc.Types.val_uid;
                  name = String.concat "." names;
                  labels = labels 32 desc.val_type;
                  role;
                }
            with Not_found | Env.Error _ | Persistent_env.Error _ -> None))
      names
  in
  let heads =
    catalogue Worker
      (List.map
         (fun n -> [ "Ox_blocking"; n ])
         [
           "run";
           "try_run";
           "run_result";
           "try_run_result";
           "run_result_timeout";
           "try_run_result_timeout";
           "run_leased_result";
         ])
    @ catalogue Eio
        (List.map
           (fun n -> [ "Eio"; "Fiber"; n ])
           [ "yield"; "check"; "await_cancel"; "both"; "pair"; "first" ]
        @ List.map
            (fun n -> [ "Eio"; "Fiber"; n ])
            [ "fork"; "fork_promise"; "fork_daemon" ]
        @ [
            [ "Eio"; "Switch"; "run" ];
            [ "Eio"; "Cancel"; "protect" ];
            [ "Eio"; "Time"; "sleep" ];
            [ "Eio"; "Time"; "Mono"; "sleep" ];
          ])
    @ catalogue Root
        [
          [ "Eio_main"; "run" ];
          [ "Eio_linux"; "run" ];
          [ "Eio_posix"; "run" ];
          [ "Ox_test"; "run" ];
        ]
    @ catalogue Wait
        [
          [ "Unix"; "sleep" ];
          [ "Unix"; "sleepf" ];
          [ "Thread"; "delay" ];
          [ "Thread"; "join" ];
          [ "Stdlib"; "Domain"; "join" ];
          [ "Stdlib"; "Semaphore"; "Counting"; "acquire" ];
        ]
    @ catalogue Pure [ [ "Stdlib"; "ignore" ] ]
    @ catalogue Callback [ [ "Stdlib"; "Fun"; "protect" ] ]
  in
  let definitions = Path.Tbl.create 32 and reported = Hashtbl.create 16 in
  let normalize e p = Env.normalize_value_path None (Paths.env ~caps e.exp_env) p in
  let known e p uid =
    List.find_opt
      (fun h -> Path.same h.path (normalize e p) && Shape.Uid.equal h.uid uid)
      heads
  in
  let report output context loc reason =
    match context with
    | Outside -> ()
    | Owner | Native _ ->
        let message =
          match context with
          | Native (entry, origin) ->
              Printf.sprintf "%s native callback at %s:%d: %s" entry
                origin.Location.loc_start.Lexing.pos_fname origin.loc_start.pos_lnum
                reason
          | Owner -> "Eio owner callback: " ^ reason
          | Outside -> assert false
        in
        if not (Hashtbl.mem reported (loc, message)) then (
          Hashtbl.add reported (loc, message) ();
          output loc message)
  in
  let lookup env path =
    List.find_map (fun (p, v) -> if Path.same p path then Some v else None) env
  in
  let bind pattern v env =
    List.fold_left
      (fun env id -> (Path.Pident id, v) :: env)
      env
      (Typedtree.pat_bound_idents pattern)
  in
  let take label args =
    let rec loop before = function
      | [] -> None
      | (other, v) :: rest when other = label -> Some (v, List.rev_append before rest)
      | arg :: rest -> loop (arg :: before) rest
    in
    loop [] args
  in
  let rec supplied args = function
    | [] -> true
    | label :: rest -> (
        match take label args with None -> false | Some (_, args) -> supplied args rest)
  in
  (* This search selects actual known identities, including defaults and captured values.
     Its absence is only outside this catalogue, never a purity/context certificate. *)
  let interesting context h =
    match context with
    | Outside -> false
    | Owner -> h.role = Wait
    | Native _ -> h.role = Eio || h.role = Worker
  in
  let rec candidate context seen = function
    | Head (h, _) -> interesting context h
    | Boolean _ -> false
    | Group vs -> List.exists (candidate context seen) vs
    | Optional_value value -> Option.fold ~none:false ~some:(candidate context seen) value
    | Closure (e, env, _) -> candidate_expr context seen env e
  and candidate_expr context seen env e =
    if List.exists (fun old -> old == e) seen then false
    else
      let seen = e :: seen and found = ref false in
      let visitor =
        {
          base with
          expr =
            (fun self child ->
              (match child.exp_desc with
              | Texp_ident { path; desc; _ } -> (
                  let path = normalize child path in
                  if
                    Option.fold ~none:false ~some:(interesting context)
                      (known child path desc.val_uid)
                  then found := true
                  else
                    match lookup env path with
                    | Some v -> if candidate context seen v then found := true
                    | None ->
                        Option.iter
                          (fun body ->
                            if candidate_expr context seen env body then found := true)
                          (Path.Tbl.find_opt definitions path))
              | _ -> ());
              if not !found then base.expr self child);
        }
      in
      visitor.expr visitor e;
      !found
  in
  let data = Group [] in
  let rec eval context fuel active env e =
    if !fuel <= 0 then
      if candidate_expr context [] env e then (
        report undecided context e.exp_loc
          "unresolved known execution-context candidate at local analysis horizon";
        Group [ Closure (e, env, []) ])
      else data
    else (
      decr fuel;
      match e.exp_desc with
      | Texp_ident { path; desc; _ } -> (
          let path = normalize e path in
          match lookup env path with
          | Some v -> v
          | None -> (
              match known e path desc.val_uid with
              | Some h -> Head (h, [])
              | None -> (
                  match Path.Tbl.find_opt definitions path with
                  | Some body -> eval Outside fuel active env body
                  | _ -> data)))
      | Texp_construct (_, desc, _, [], _)
        when type_path_matches 32 Predef.path_bool e.exp_type ->
          Boolean (desc.cstr_name = "true")
      | Texp_construct (_, _, _, [], _)
        when type_path_matches 32 Predef.path_option e.exp_type ->
          Optional_value None
      | Texp_construct (_, _, _, [ (_, value) ], _)
        when type_path_matches 32 Predef.path_option e.exp_type ->
          Optional_value (Some (eval context fuel active env value))
      | Texp_function _ -> Closure (e, env, [])
      | Texp_apply (fn, args, _, _, _) ->
          let v = eval context fuel active env fn in
          let args =
            List.filter_map
              (function
                | label, Arg (e, _) -> Some (label, eval context fuel active env e)
                | _ -> None)
              args
          in
          invoke context fuel active fn.exp_loc v args
      | Texp_let (_, bindings, body) ->
          let values =
            List.map (fun vb -> (vb, eval context fuel active env vb.vb_expr)) bindings
          in
          let env = List.fold_left (fun env (vb, v) -> bind vb.vb_pat v env) env values in
          eval context fuel active env body
      | Texp_sequence (first, _, last) ->
          ignore (eval context fuel active env first);
          eval context fuel active env last
      | Texp_ifthenelse (condition, yes, no) -> (
          match eval context fuel active env condition with
          | Boolean true -> eval context fuel active env yes
          | Boolean false ->
              Option.fold ~none:data ~some:(eval context fuel active env) no
          | _ ->
              Group
                (eval context fuel active env yes
                :: Option.to_list (Option.map (eval context fuel active env) no)))
      | Texp_match (scrutinee, _, cases, _, _) ->
          let value = eval context fuel active env scrutinee in
          Group
            (List.map
               (fun case ->
                 let env = bind case.c_lhs value env in
                 Option.iter
                   (fun guard -> ignore (eval context fuel active env guard))
                   case.c_guard;
                 eval context fuel active env case.c_rhs)
               cases)
      | Texp_open (_, body) | Texp_exclave body -> eval context fuel active env body
      | Texp_lazy _ | Texp_object _ -> Group [ Closure (e, env, []) ]
      | _ ->
          let values = ref [] in
          let visitor =
            {
              base with
              expr =
                (fun _ child -> values := eval context fuel active env child :: !values);
            }
          in
          base.expr visitor e;
          Group !values)
  and invoke context fuel active loc value args =
    match value with
    | Head (h, saved) -> (
        let args = saved @ args in
        if not (supplied args h.labels) then Head (h, args)
        else
          match h.role with
          | Worker ->
              (match context with
              | Native _ ->
                  report emit context loc (h.name ^ " requires the Eio caller context")
              | Outside | Owner ->
                  Option.iter
                    (fun (callback, _) ->
                      ignore
                        (invoke
                           (Native (h.name, loc))
                           (ref 512) [] loc callback
                           [ (Nolabel, data) ]))
                    (take Nolabel args));
              data
          | Wait ->
              (match context with
              | Owner -> report emit context loc (h.name ^ " blocks the Eio owner thread")
              | _ -> ());
              data
          | Pure -> data
          | Eio | Root | Callback ->
              let native = match context with Native _ -> true | _ -> false in
              if h.role = Eio && native then
                report emit context loc (h.name ^ " requires an Eio fiber context")
              else
                List.iter
                  (fun (_, v) ->
                    match v with
                    | Closure _ | Head _ ->
                        let callback_args =
                          if h.name = "Ox_test.run" then
                            [ (Nolabel, data); (Nolabel, data) ]
                          else [ (Nolabel, data) ]
                        in
                        ignore
                          (invoke
                             (if h.role = Callback then context else Owner)
                             fuel active loc v callback_args)
                    | _ -> ())
                  args;
              data)
    | Boolean _ -> data
    | Optional_value value ->
        invoke context fuel active loc (Group (Option.to_list value)) args
    | Group values ->
        let values = values @ List.map snd args in
        if List.exists (candidate context []) values then
          report undecided context loc
            "unresolved known execution-context value escaping opaque call or scope";
        Group values
    | Closure (closure, captured, saved) -> (
        let args = saved @ args in
        match closure.exp_desc with
        | Texp_function { params; body; _ } -> (
            let required =
              List.filter_map
                (fun p -> match p.fp_arg_label with Optional _ -> None | l -> Some l)
                params
            in
            let required =
              match body with
              | Tfunction_cases _ -> required @ [ Nolabel ]
              | _ -> required
            in
            if not (supplied args required) then Closure (closure, captured, args)
            else if
              List.exists (fun old -> old == closure) active || List.length active >= 32
            then (
              if candidate context [] value then
                report undecided context loc
                  "unresolved recursive known execution-context helper or local call \
                   horizon";
              data)
            else
              let env, remaining =
                List.fold_left
                  (fun (env, args) p ->
                    let v, args =
                      match take p.fp_arg_label args with
                      | Some pair -> pair
                      | None -> (data, args)
                    in
                    let pattern, v =
                      match p.fp_kind with
                      | Tparam_pat p -> (p, v)
                      | Tparam_optional_default (p, default, _) -> (
                          match v with
                          | Optional_value (Some value) -> (p, value)
                          | _ ->
                              if candidate_expr context [] env default then
                                report undecided context loc
                                  "unresolved optional default containing known \
                                   execution-context candidate";
                              (p, v))
                    in
                    (bind pattern v ((Path.Pident p.fp_param, v) :: env), args))
                  (captured, args) params
              in
              let active = closure :: active in
              match body with
              | Tfunction_body body ->
                  let result = eval context fuel active env body in
                  if remaining = [] then result
                  else invoke context fuel active loc result remaining
              | Tfunction_cases cases ->
                  let v =
                    match take Nolabel remaining with Some (v, _) -> v | None -> data
                  in
                  Group
                    (List.map
                       (fun case ->
                         let env = bind case.c_lhs v env in
                         Option.iter
                           (fun guard -> ignore (eval context fuel active env guard))
                           case.c_guard;
                         eval context fuel active env case.c_rhs)
                       cases.fc_cases))
        | _ -> data)
  in
  let remember ?parent vb =
    List.iter
      (fun id ->
        Path.Tbl.replace definitions (Path.Pident id) vb.vb_expr;
        Option.iter
          (fun parent ->
            Path.Tbl.replace definitions (Path.Pdot (parent, Ident.name id)) vb.vb_expr)
          parent)
      (Typedtree.pat_bound_idents vb.vb_pat)
  in
  let rec collect_module parent m =
    match m.mod_desc with
    | Tmod_structure tree ->
        List.iter
          (fun item ->
            match item.str_desc with
            | Tstr_value (_, bs) -> List.iter (remember ~parent) bs
            | Tstr_module mb ->
                Option.iter
                  (fun id ->
                    collect_module (Path.Pdot (parent, Ident.name id)) mb.mb_expr)
                  mb.mb_id
            | _ -> ())
          tree.str_items
    | Tmod_constraint (m, _, _, _) -> collect_module parent m
    | _ -> ()
  in
  let collector =
    {
      base with
      value_binding =
        (fun self vb ->
          remember vb;
          base.value_binding self vb);
      module_binding =
        (fun self mb ->
          Option.iter (fun id -> collect_module (Path.Pident id) mb.mb_expr) mb.mb_id;
          base.module_binding self mb);
    }
  in
  {
    base with
    structure =
      (fun self tree ->
        collector.structure collector tree;
        base.structure self tree);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) -> (
            let fuel = ref 512 in
            let v = eval Outside fuel [] [] fn in
            match v with
            | Head ({ role = Worker | Root; _ }, _) ->
                let args =
                  List.filter_map
                    (function
                      | l, Arg (e, _) -> Some (l, eval Outside fuel [] [] e) | _ -> None)
                    args
                in
                ignore (invoke Outside fuel [] fn.exp_loc v args)
            | _ -> ())
        | _ -> ());
        base.expr self e);
  }
