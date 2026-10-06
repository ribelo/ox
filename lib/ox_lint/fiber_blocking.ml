(* ^safe-9ved ^safe-r5ye ^safe-ohen: finite compiler-identity execution proof. *)
open Ocaml_common
open Typedtree

let base = Tast_iterator.default_iterator

type value =
  | Data
  | Open_flag of bool
  | Descriptor of bool option ref
  | Unknown of string
  | Closure of expression * environment * (arg_label * value) list
  | Operation of Path.t * (arg_label * value) list
  | Alternatives of value list
  | Container of value list

and environment = (Path.t * value) list

let check ~caps ~emit ~undecided =
  let identities = ref [] in
  let catalogue entries =
    List.filter_map
      (fun (((first, rest) as names), detail) ->
        Option.map
          (fun path ->
            let _, descriptor, _ =
              Env.lookup_value ~use:false ~loc:Location.none (Paths.lid names)
                (Lazy.force Env.initial)
            in
            let name =
              if names = ("Stdlib", [ "Domain"; "join" ]) then "Domain.join"
              else String.concat "." (first :: rest)
            in
            identities := (path, descriptor.Types.val_uid, name) :: !identities;
            (path, (name, detail)))
          (Paths.value ~caps names))
      entries
  in
  let roots =
    catalogue
      [
        (("Eio_main", [ "run" ]), 1);
        (("Eio_linux", [ "run" ]), 1);
        (("Eio_posix", [ "run" ]), 1);
        (("Ox_test", [ "run" ]), 1);
      ]
  in
  let waits =
    catalogue
      [
        (("Unix", [ "read" ]), 4);
        (("Unix", [ "write" ]), 4);
        (("Unix", [ "sleep" ]), 1);
        (("Unix", [ "sleepf" ]), 1);
        (("Thread", [ "delay" ]), 1);
        (("Thread", [ "join" ]), 1);
        (("Stdlib", [ "Domain"; "join" ]), 1);
        (("Stdlib", [ "Semaphore"; "Counting"; "acquire" ]), 1);
      ]
  in
  let workers =
    catalogue
      (List.map
         (fun name -> (("Ox_blocking", [ name ]), 1))
         [
           "run";
           "try_run";
           "run_result";
           "run_leased_result";
           "try_run_result";
           "run_result_timeout";
           "try_run_result_timeout";
         ])
  in
  let required_labels =
    catalogue
      (List.map
         (fun name ->
           ( ("Ox_blocking", [ name ]),
             if String.ends_with ~suffix:"_timeout" name then
               [ "pool"; "clock"; "timeout"; "on_timeout" ]
             else if name = "run_leased_result" then [ "pool"; "release" ]
             else [ "pool" ] ))
         [
           "run";
           "try_run";
           "run_result";
           "run_leased_result";
           "try_run_result";
           "run_result_timeout";
           "try_run_result_timeout";
         ]
      @ List.map
          (fun name -> (("Eio", [ "Fiber"; name ]), [ "sw" ]))
          [ "fork"; "fork_promise"; "fork_daemon" ]
      @ [ (("Stdlib", [ "Fun"; "protect" ]), [ "finally" ]) ])
  in
  let callbacks =
    catalogue
      [
        (("Eio", [ "Fiber"; "both" ]), 2);
        (("Eio", [ "Fiber"; "pair" ]), 2);
        (("Eio", [ "Fiber"; "first" ]), 2);
        (("Eio", [ "Fiber"; "fork" ]), 1);
        (("Eio", [ "Fiber"; "fork_promise" ]), 1);
        (("Eio", [ "Fiber"; "fork_daemon" ]), 1);
        (("Eio", [ "Switch"; "run" ]), 1);
        (("Eio", [ "Cancel"; "protect" ]), 1);
        (("Stdlib", [ "Fun"; "protect" ]), 1);
        (("Stdlib", [ "Option"; "iter" ]), 2);
      ]
  in
  (* Only facts required by descriptor tracking and the cooperative wait controls. *)
  let leaves =
    catalogue
      [
        (("Stdlib", [ "ignore" ]), 1);
        (("Unix", [ "openfile" ]), 3);
        (("Unix", [ "set_nonblock" ]), 1);
        (("Unix", [ "clear_nonblock" ]), 1);
        (("Eio", [ "Time"; "sleep" ]), 2);
        (("Eio", [ "Time"; "Mono"; "sleep" ]), 2);
        (("Eio", [ "Semaphore"; "acquire" ]), 1);
      ]
  in
  let flags =
    try
      let _, declaration =
        Env.lookup_type ~use:false ~loc:Location.none
          (Paths.lid ("Unix", [ "open_flag" ]))
          (Lazy.force Env.initial)
      in
      match declaration.Types.type_kind with
      | Type_variant (constructors, _, _) ->
          List.map
            (fun c -> (c.Types.cd_uid, Ident.name c.cd_id = "O_NONBLOCK"))
            constructors
      | _ -> []
    with Not_found | Env.Error _ -> []
  in
  let rec descriptor_escape = function
    | Descriptor state -> state := None
    | Alternatives values | Container values -> List.iter descriptor_escape values
    | Closure (_, captured, _) ->
        List.iter (fun (_, value) -> descriptor_escape value) captured
    | _ -> ()
  in
  let rec nonblock_flags = function
    | Open_flag value -> Some value
    | Container values ->
        let values = List.map nonblock_flags values in
        if List.exists Option.is_none values then None
        else Some (List.exists (fun x -> x = Some true) values)
    | _ -> None
  in
  let alternatives env branches =
    let states = ref [] in
    let rec collect = function
      | Descriptor state ->
          if not (List.exists (fun (other, _) -> state == other) !states) then
            states := (state, !state) :: !states
      | Closure (_, captured, _) -> List.iter (fun (_, value) -> collect value) captured
      | Alternatives values | Container values -> List.iter collect values
      | _ -> ()
    in
    List.iter (fun (_, value) -> collect value) env;
    let results =
      List.map
        (fun branch ->
          List.iter (fun (state, original) -> state := original) !states;
          let value = branch () in
          (value, List.map (fun (state, _) -> !state) !states))
        branches
    in
    List.iteri
      (fun index (state, original) ->
        match results with
        | [] -> state := original
        | (_, first) :: rest ->
            let value = List.nth first index in
            state :=
              if List.for_all (fun (_, values) -> List.nth values index = value) rest then
                value
              else None)
      !states;
    Alternatives (List.map fst results)
  in
  let find catalogue path =
    List.find_map
      (fun (expected, detail) -> if Path.same expected path then Some detail else None)
      catalogue
  in
  let definitions = Path.Tbl.create 32 in
  let references = Path.Tbl.create 16 in
  let reported = Hashtbl.create 32 in
  let proven = Hashtbl.create 16 in
  let report output context loc reason =
    match context with
    | None -> ()
    | Some (entry, origin, uncertain) ->
        if output == emit && not uncertain then
          Hashtbl.replace proven (loc, entry, origin) ();
        let message =
          Printf.sprintf "%s Eio callback at %s:%d: %s" entry
            origin.Location.loc_start.Lexing.pos_fname origin.loc_start.pos_lnum reason
        in
        let message =
          if uncertain then
            message ^ "; owner execution context cannot be established for this candidate"
          else message
        in
        let key = (loc, message) in
        if not (Hashtbl.mem reported key) then (
          Hashtbl.add reported key ();
          (if uncertain then undecided else output) loc message)
  in
  let normalize e path = Env.normalize_value_path None (Paths.env ~caps e.exp_env) path in
  (* Only a unit-parameter tail loop of one compiler-identified cooperative sleep
     has a stable operation summary. Changed arguments and arbitrary recursion do not. *)
  let candidate_unknown context expression reason =
    let visitor =
      {
        base with
        expr =
          (fun self e ->
            (match e.exp_desc with
            | Texp_ident { path; _ } -> (
                match find waits (normalize e path) with
                | Some (name, _) ->
                    let already_proven =
                      match context with
                      | Some (entry, origin, _) ->
                          Hashtbl.mem proven (e.exp_loc, entry, origin)
                      | None -> false
                    in
                    if
                      not
                        (already_proven
                        && reason
                           = "unresolved recursive helper or 32-call analysis horizon"
                        && name <> "Unix.read" && name <> "Unix.write")
                    then report undecided context e.exp_loc (name ^ ": " ^ reason)
                | None -> ())
            | _ -> ());
            base.expr self e);
      }
    in
    visitor.expr visitor expression
  in
  let cooperative_tail_loop closure =
    let call_path expr =
      match expr.exp_desc with
      | Texp_apply (({ exp_desc = Texp_ident { path; _ }; _ } as fn), _, _, _, _) ->
          Some (normalize fn path)
      | _ -> None
    in
    match closure.exp_desc with
    | Texp_function
        {
          params = [ param ];
          body = Tfunction_body { exp_desc = Texp_sequence (pause, _, again); _ };
          _;
        } -> (
        let unit_param =
          match param.fp_kind with
          | Tparam_pat pattern -> (
              match (pattern.pat_desc, Types.get_desc pattern.pat_type) with
              | Tpat_construct _, Tconstr (path, _, _) -> Path.same path Predef.path_unit
              | _ -> false)
          | _ -> false
        in
        unit_param
        &&
        match (call_path pause, call_path again) with
        | Some pause, Some again -> (
            (match find leaves pause with
              | Some ("Eio.Time.sleep", _) | Some ("Eio.Time.Mono.sleep", _) -> true
              | _ -> false)
            &&
            match Path.Tbl.find_opt definitions again with
            | Some self -> self == closure
            | None -> false)
        | _ -> false)
    | _ -> false
  in
  let bind pattern value env =
    List.fold_left
      (fun env id -> (Path.Pident id, value) :: env)
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
  (* Resolve only a supplied wait-bearing callback, never arbitrary Root closures.
     A fresh implementation/interface pair proves this one native forwarding fact:
     the callback's sole compiler-UID use is a saturated Ox_blocking job argument. *)
  let native_forward path args =
    let has_wait value =
      let found = ref false and seen = ref [] and remaining = ref 128 in
      let rec value_scan = function
        | Operation (path, _) -> if Option.is_some (find waits path) then found := true
        | Closure (expression, captured, _) ->
            expression_scan expression;
            List.iter (fun (_, value) -> value_scan value) captured
        | Container values | Alternatives values -> List.iter value_scan values
        | _ -> ()
      and expression_scan expression =
        let visitor =
          {
            base with
            expr =
              (fun self e ->
                if !remaining > 0 && not (List.exists (( == ) e) !seen) then (
                  decr remaining;
                  seen := e :: !seen;
                  (match e.exp_desc with
                  | Texp_ident { path; _ } ->
                      let path = normalize e path in
                      if Option.is_some (find waits path) then found := true
                      else
                        Option.iter expression_scan (Path.Tbl.find_opt definitions path)
                  | _ -> ());
                  base.expr self e));
          }
        in
        visitor.expr visitor expression
      in
      value_scan value;
      !found
    in
    match List.filter (fun (label, _) -> label = Nolabel) args with
    | [ (Nolabel, job) ] when has_wait job -> (
        try
          let reference = Path.Tbl.find references path in
          let descriptor =
            match reference.exp_desc with
            | Texp_ident { desc; _ } -> desc
            | _ -> raise Not_found
          in
          let authentic =
            Env.find_value path (Paths.env ~caps reference.exp_env)
            |> Subst.Lazy.force_value_description
          in
          if not (Types.Uid.equal descriptor.Types.val_uid authentic.Types.val_uid) then
            raise Not_found;
          let unit_name, name =
            match path with
            | Path.Pdot (Path.Pident id, name) when Ident.is_global id ->
                (Ident.name id, name)
            | _ -> raise Not_found
          in
          let current = Option.get (Artifact.current ()) in
          let imported =
            Array.find_opt
              (fun imported ->
                Compilation_unit.Name.to_string (Import_info.name imported) = unit_name)
              current.Artifact.info.cmt_imports
            |> Option.get
          in
          let crc = Import_info.crc imported |> Option.get in
          let annotation =
            Load_path.find (String.uncapitalize_ascii unit_name ^ ".cmt")
          in
          let artifact = Artifact.read ~caps annotation in
          let own_import =
            Array.find_opt
              (fun imported ->
                Compilation_unit.Name.to_string (Import_info.name imported) = unit_name)
              artifact.info.cmt_imports
          in
          let linked =
            artifact.info.cmt_interface_digest = Some crc
            || Option.bind own_import Import_info.crc = Some crc
          in
          if
            Compilation_unit.name_as_string artifact.info.cmt_modname <> unit_name
            || not linked
          then raise Not_found;
          let source = Artifact.authored_source ~caps artifact in
          Artifact.check ~caps ~source artifact;
          let structure =
            match artifact.info.cmt_annots with
            | Cmt_format.Implementation structure -> structure
            | _ -> raise Not_found
          in
          let binding =
            List.find_map
              (fun item ->
                match item.str_desc with
                | Tstr_value (_, bindings) ->
                    List.find_opt
                      (fun binding ->
                        List.exists
                          (fun id -> Ident.name id = name)
                          (Typedtree.pat_bound_idents binding.vb_pat))
                      bindings
                | _ -> None)
              (List.rev structure.str_items)
            |> Option.get
          in
          let params, body =
            match binding.vb_expr.exp_desc with
            | Texp_function { params; body = Tfunction_body body; _ } -> (params, body)
            | _ -> raise Not_found
          in
          let param =
            match List.filter (fun p -> p.fp_arg_label = Nolabel) params with
            | [ param ] -> param
            | _ -> raise Not_found
          in
          let uid =
            match param.fp_kind with
            | Tparam_pat { pat_desc = Tpat_var { uid; _ }; _ } -> uid
            | _ -> raise Not_found
          in
          let saturated =
            List.for_all
              (fun p ->
                match p.fp_arg_label with
                | Optional _ -> true
                | label -> List.exists (fun (provided, _) -> provided = label) args)
              params
          in
          let uses = ref 0 and native = ref false and wait = ref false in
          let visitor =
            {
              base with
              expr =
                (fun self e ->
                  (match e.exp_desc with
                  | Texp_ident { path; desc; _ } ->
                      if Types.Uid.equal uid desc.Types.val_uid then incr uses;
                      if Option.is_some (find waits (normalize e path)) then wait := true
                  | Texp_apply
                      ( ({ exp_desc = Texp_ident { path; desc; _ }; _ } as fn),
                        call_args,
                        _,
                        _,
                        _ ) -> (
                      let path = normalize fn path in
                      let genuine =
                        List.exists
                          (fun (expected, uid, _) ->
                            Path.same expected path
                            && Types.Uid.equal uid desc.Types.val_uid)
                          !identities
                      in
                      let positional =
                        List.filter_map
                          (function Nolabel, Arg (e, _) -> Some e | _ -> None)
                          call_args
                      in
                      let labels =
                        match find required_labels path with
                        | Some (_, labels) -> labels
                        | None -> []
                      in
                      let saturated =
                        List.for_all
                          (fun name ->
                            List.exists
                              (function
                                | Labelled label, Arg _ when label = name -> true
                                | _ -> false)
                              call_args)
                          labels
                      in
                      match (find workers path, positional) with
                      | Some _, [ { exp_desc = Texp_ident { desc; _ }; _ } ]
                        when genuine && saturated
                             && Types.Uid.equal uid desc.Types.val_uid ->
                          let unit_name =
                            Compilation_unit.Name.of_string (Ident.name (Path.head path))
                          in
                          let imported =
                            Array.find_opt
                              (fun imported ->
                                Import_info.has_name imported ~name:unit_name)
                              artifact.info.cmt_imports
                            |> Option.get
                          in
                          let expected = Import_info.crc imported |> Option.get in
                          let filename =
                            String.uncapitalize_ascii
                              (Compilation_unit.Name.to_string unit_name)
                            ^ ".cmi"
                          in
                          let cmi = Cmi_format.read_cmi (Load_path.find filename) in
                          if
                            not
                              (Array.exists
                                 (fun imported ->
                                   Import_info.has_name imported ~name:unit_name
                                   && Import_info.crc imported = Some expected)
                                 cmi.cmi_crcs)
                          then raise Not_found;
                          native := true
                      | _ -> ())
                  | _ -> ());
                  base.expr self e);
            }
          in
          visitor.expr visitor body;
          if !native && !uses = 1 && not !wait then
            Some (if saturated then `Native else `Partial)
          else None
        with
        | Not_found | Invalid_argument _ | Failure _ | Sys_error _ | Env.Error _
        | Cmi_format.Error _ | Cmt_format.Error _
        ->
          None)
    | _ -> None
  in
  let rec eval context budget active aliases env e =
    if !budget <= 0 then (
      candidate_unknown context e "unresolved 512-expression analysis horizon";
      Unknown "analysis horizon")
    else (
      decr budget;
      match e.exp_desc with
      | Texp_ident { path; _ } -> (
          let path = normalize e path in
          match
            List.find_map (fun (p, v) -> if Path.same p path then Some v else None) env
          with
          | Some v -> v
          | None when List.exists (Path.same path) aliases ->
              Unknown ("cyclic alias " ^ Path.name path)
          | None -> (
              match Path.Tbl.find_opt definitions path with
              | Some definition -> (
                  match definition.exp_desc with
                  | Texp_function _ | Texp_ident _ | Texp_apply _ ->
                      eval None budget active (path :: aliases) env definition
                  | _ -> Unknown ("computed binding " ^ Path.name path))
              | None ->
                  Path.Tbl.replace references path e;
                  Operation (path, [])))
      | Texp_function _ -> Closure (e, env, [])
      | Texp_apply (fn, args, _, _, _) ->
          let value = eval context budget active aliases env fn in
          let args =
            List.filter_map
              (function
                | label, Arg (arg, _) ->
                    Some (label, eval context budget active aliases env arg)
                | _ -> None)
              args
          in
          invoke context budget active env fn.exp_loc value args
      | Texp_let (_, bindings, body) ->
          let values =
            List.map
              (fun vb -> (vb, eval context budget active aliases env vb.vb_expr))
              bindings
          in
          let env = List.fold_left (fun env (vb, v) -> bind vb.vb_pat v env) env values in
          eval context budget active aliases env body
      | Texp_sequence (first, _, last) ->
          ignore (eval context budget active aliases env first);
          eval context budget active aliases env last
      | Texp_match (scrutinee, _, cases, _, _) ->
          let value = eval context budget active aliases env scrutinee in
          alternatives env
            (List.map
               (fun case () ->
                 let env = bind case.c_lhs value env in
                 Option.iter
                   (fun guard -> ignore (eval context budget active aliases env guard))
                   case.c_guard;
                 eval context budget active aliases env case.c_rhs)
               cases)
      | Texp_ifthenelse (condition, yes, no) ->
          ignore (eval context budget active aliases env condition);
          alternatives env
            [
              (fun () -> eval context budget active aliases env yes);
              (fun () ->
                match no with
                | None -> Data
                | Some no -> eval context budget active aliases env no);
            ]
      | Texp_open (_, body) | Texp_exclave body ->
          eval context budget active aliases env body
      | Texp_construct (_, constructor, _, values, _) -> (
          match
            List.find_opt (fun (uid, _) -> Types.Uid.equal uid constructor.cstr_uid) flags
          with
          | Some (_, nonblock) -> Open_flag nonblock
          | None ->
              Container
                (List.map
                   (fun (_, value) -> eval context budget active aliases env value)
                   values))
      | Texp_lazy _ -> Unknown "dormant lazy value"
      | Texp_send _ ->
          candidate_unknown context e "unresolved dynamic object method execution";
          Unknown "dynamic object method result"
      | Texp_object _ | Texp_pack _ ->
          candidate_unknown context e "unresolved object or first-class module execution";
          Unknown "object or first-class module"
      | _ ->
          let visitor =
            {
              base with
              expr =
                (fun _ child -> ignore (eval context budget active aliases env child));
            }
          in
          base.expr visitor e;
          Data)
  and invoke context budget active env loc value args =
    match value with
    | Alternatives values ->
        Alternatives
          (List.map (fun v -> invoke context budget active env loc v args) values)
    | Unknown _ ->
        uncertain_arguments context budget active env loc args;
        value
    | Container values ->
        let rec transfer = function
          | Operation (path, _) -> (
              match find waits path with
              | Some (name, _) ->
                  report undecided context loc
                    (name ^ ": unresolved compound callee containing known wait")
              | None -> ())
          | Container values | Alternatives values -> List.iter transfer values
          | Closure _ as value ->
              uncertain_arguments context budget active env loc [ (Nolabel, value) ]
          | _ -> ()
        in
        List.iter transfer values;
        uncertain_arguments context budget active env loc args;
        Unknown "computed callee"
    | Data | Open_flag _ | Descriptor _ ->
        uncertain_arguments context budget active env loc args;
        Unknown "computed callee"
    | Operation (path, saved) -> (
        let args = saved @ args in
        let positional = List.filter (fun (label, _) -> label = Nolabel) args in
        let arity =
          match
            ( find roots path,
              find waits path,
              find workers path,
              find callbacks path,
              find leaves path )
          with
          | Some (_, n), _, _, _, _
          | _, Some (_, n), _, _, _
          | _, _, Some (_, n), _, _
          | _, _, _, Some (_, n), _
          | _, _, _, _, Some (_, n) ->
              n
          | _ -> 1
        in
        let labels_available =
          match find required_labels path with
          | None -> true
          | Some (_, labels) ->
              List.for_all
                (fun label -> Option.is_some (take (Labelled label) args))
                labels
        in
        let hook label count =
          List.iter
            (fun (supplied, callback) ->
              let values =
                match supplied with
                | Optional name when name = label -> (
                    match callback with Container values -> values | value -> [ value ])
                | Labelled name when name = label -> [ callback ]
                | _ -> []
              in
              List.iter
                (fun callback ->
                  ignore
                    (invoke context budget active env loc callback
                       (List.init count (fun _ -> (Nolabel, Data)))))
                values)
            args
        in
        if List.length positional < arity || not labels_available then
          Operation (path, args)
        else
          match
            ( find roots path,
              find waits path,
              find workers path,
              find callbacks path,
              find leaves path )
          with
          | Some (entry, _), _, _, _, _ ->
              let callback = snd (List.hd positional) in
              ignore
                (invoke
                   (Some (entry, loc, false))
                   budget active env loc callback
                   (List.init
                      (if entry = "Ox_test.run" then 2 else 1)
                      (fun _ -> (Nolabel, Data))));
              Data
          | _, Some (name, _), _, _, _ ->
              let replacement =
                if name = "Stdlib.Semaphore.Counting.acquire" then
                  " may synchronously wait on the scheduler domain; use \
                   Eio.Semaphore.acquire in the owner fiber, or Ox_blocking.run ~pool"
                else if name = "Thread.join" || name = "Domain.join" then
                  " may synchronously wait on the scheduler domain; join outside the Eio \
                   owner, or use Ox_blocking.run ~pool"
                else
                  " synchronously waits on the scheduler domain; use Eio.Time.sleep with \
                   an explicit clock, or Ox_blocking.run ~pool"
              in
              if name = "Unix.read" || name = "Unix.write" then
                match snd (List.hd positional) with
                | Descriptor state when !state = Some true ->
                    report emit context loc
                      (name
                     ^ " on a proven blocking descriptor may synchronously wait on the \
                        scheduler domain; use Eio.Flow in the owner fiber, or \
                        Ox_blocking.run ~pool")
                | Descriptor state when !state = Some false -> ()
                | _ ->
                    report undecided context loc
                      (name
                     ^ ": descriptor blocking mode is unresolved; audit its creation and \
                        flag changes before claiming owner safety")
              else report emit context loc (name ^ replacement);
              Data
          | _, _, Some (name, _), _, _ ->
              (* Only the last job thunk transfers to native execution. Argument expressions,
                 cancellation/settlement hooks and leased releases remain owner Eio work. *)
              List.iter
                (fun (label, value) -> if label = Nolabel then descriptor_escape value)
                args;
              hook "on_cancel" 1;
              hook "on_settled" 1;
              if name = "Ox_blocking.run_leased_result" then hook "release" 1;
              Data
          | _, _, _, Some (name, _), _ ->
              if name = "Eio.Fiber.first" then hook "combine" 2;
              if name = "Stdlib.Fun.protect" then hook "finally" 1;
              let option_values =
                match
                  snd (List.nth positional (if name = "Stdlib.Option.iter" then 1 else 0))
                with
                | Container values -> values
                | _ -> [ Data ]
              in
              let positional =
                if name = "Stdlib.Option.iter" then
                  List.map (fun value -> (value, snd (List.hd positional))) option_values
                else List.map (fun (_, callback) -> (Data, callback)) positional
              in
              List.iter
                (fun (argument, callback) ->
                  ignore
                    (invoke context budget active env loc callback
                       [ (Nolabel, argument) ]))
                positional;
              Data
          | _, _, _, _, Some (name, _) ->
              if name = "Unix.openfile" then
                Descriptor
                  (ref
                     (if Option.is_some context then
                        Option.map not (nonblock_flags (snd (List.nth positional 1)))
                      else None))
              else if name = "Unix.set_nonblock" || name = "Unix.clear_nonblock" then (
                (match snd (List.hd positional) with
                | Descriptor state -> state := Some (name = "Unix.clear_nonblock")
                | _ -> ());
                Data)
              else Data
          | _ -> (
              let transfer =
                if Option.is_some context then native_forward path args else None
              in
              match transfer with
              | Some `Partial -> Operation (path, args)
              | _ ->
                  let owner_args =
                    if transfer = Some `Native then
                      List.filter (fun (label, _) -> label <> Nolabel) args
                    else args
                  in
                  uncertain_arguments context budget active env loc owner_args;
                  List.iter (fun (_, value) -> descriptor_escape value) args;
                  Unknown ("external return " ^ Path.name path)))
    | Closure (closure, captured, saved) -> (
        let args = saved @ args in
        match closure.exp_desc with
        | Texp_function { params; body; _ } -> (
            let required =
              List.filter
                (fun p -> match p.fp_arg_label with Optional _ -> false | _ -> true)
                params
            in
            let rec available args = function
              | [] -> (
                  match body with
                  | Tfunction_body _ -> true
                  | Tfunction_cases _ -> Option.is_some (take Nolabel args))
              | p :: rest -> (
                  match take p.fp_arg_label args with
                  | None -> false
                  | Some (_, args) -> available args rest)
            in
            if not (available args required) then Closure (closure, captured, args)
            else if
              List.exists (fun other -> other == closure) active
              && cooperative_tail_loop closure
            then Data
            else if
              List.exists (fun other -> other == closure) active
              || List.length active >= 32
            then (
              candidate_unknown context closure
                "unresolved recursive helper or 32-call analysis horizon";
              Unknown "recursive helper")
            else
              let env, remaining =
                List.fold_left
                  (fun (env, args) p ->
                    let supplied, args =
                      match take p.fp_arg_label args with
                      | Some (value, args) -> (Some value, args)
                      | None -> (None, args)
                    in
                    let pattern, value =
                      match p.fp_kind with
                      | Tparam_pat pattern ->
                          (pattern, Option.value ~default:(Container []) supplied)
                      | Tparam_optional_default (pattern, default, _) ->
                          let default () =
                            eval context budget (closure :: active) [] env default
                          in
                          let value =
                            match supplied with
                            | None | Some (Container []) -> default ()
                            | Some (Container [ value ]) -> value
                            | Some value -> Alternatives [ value; default () ]
                          in
                          (pattern, value)
                    in
                    (bind pattern value ((Path.Pident p.fp_param, value) :: env), args))
                  (captured, args) params
              in
              let active = closure :: active in
              match body with
              | Tfunction_body body ->
                  let result = eval context budget active [] env body in
                  if remaining = [] then result
                  else invoke context budget active env loc result remaining
              | Tfunction_cases cases ->
                  let v =
                    match take Nolabel remaining with
                    | Some (v, _) -> v
                    | None -> Unknown "case argument"
                  in
                  Alternatives
                    (List.map
                       (fun case ->
                         let env = bind case.c_lhs v env in
                         Option.iter
                           (fun guard -> ignore (eval context budget active [] env guard))
                           case.c_guard;
                         eval context budget active [] env case.c_rhs)
                       cases.fc_cases))
        | _ -> Unknown "non-function closure")
  (* Only an actual wait in a supplied callback creates an unresolved transfer candidate. *)
  and uncertain_arguments context budget active env loc args =
    let uncertain =
      Option.map (fun (entry, origin, _) -> (entry, origin, true)) context
    in
    let rec callback = function
      | Closure (({ exp_desc = Texp_function { params; body; _ }; _ } as e), _, _) as
        value ->
          let args =
            List.filter_map
              (fun p ->
                match p.fp_arg_label with
                | Optional _ -> None
                | label -> Some (label, Data))
              params
          in
          let args =
            match body with Tfunction_cases _ -> args @ [ (Nolabel, Data) ] | _ -> args
          in
          ignore (invoke uncertain budget active env e.exp_loc value args)
      | Alternatives values | Container values -> List.iter callback values
      | Operation (path, _) as value when Option.is_some (find waits path) ->
          ignore (invoke uncertain budget active env loc value [ (Nolabel, Data) ])
      | _ -> ()
    in
    List.iter
      (fun (_, value) ->
        callback value;
        descriptor_escape value)
      args
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
            | Tstr_value (_, bindings) -> List.iter (remember ~parent) bindings
            | Tstr_module binding ->
                Option.iter
                  (fun id ->
                    collect_module (Path.Pdot (parent, Ident.name id)) binding.mb_expr)
                  binding.mb_id
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
  (* Imported paths alone are insufficient evidence: a forged descriptor can otherwise
     activate a root or hide a transfer. Validate the finite catalogue before discovering
     roots; invalid evidence is undecided even if the forged root would vanish. *)
  let invalid = ref false and validated = ref false in
  let validation_sites = ref [] in
  let validator =
    {
      base with
      expr =
        (fun self e ->
          (match e.exp_desc with
          | Texp_ident { path; desc; _ } -> (
              let path = normalize e path in
              match
                List.find_opt
                  (fun (expected, _, _) -> Path.same expected path)
                  !identities
              with
              | Some (_, uid, name) when not (Types.Uid.equal uid desc.Types.val_uid) ->
                  invalid := true;
                  let message =
                    "unresolved callee identity for " ^ name
                    ^ ": declaration UID does not match imported compiler evidence"
                  in
                  if not (List.mem (e.exp_loc, message) !validation_sites) then (
                    validation_sites := (e.exp_loc, message) :: !validation_sites;
                    undecided e.exp_loc message)
              | _ -> ())
          | _ -> ());
          base.expr self e);
    }
  in
  {
    base with
    structure =
      (fun self tree ->
        if not !validated then (
          validated := true;
          validator.structure validator tree);
        if not !invalid then (
          collector.structure collector tree;
          base.structure self tree));
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, _, _, _, _) ->
            let budget = ref 512 in
            let rec root = function
              | Operation (path, _) -> Option.is_some (find roots path)
              | Alternatives vs -> List.exists root vs
              | _ -> false
            in
            if root (eval None budget [] [] [] fn) then
              ignore (eval None budget [] [] [] e)
        | _ -> ());
        base.expr self e);
  }
