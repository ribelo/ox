(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j ^nlintc-7be1 ^nlintc-4gjw. *)
open Ocaml_common
open Typedtree

let base = Tast_iterator.default_iterator

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

let catch_all emit =
  let rebindings = Path.Tbl.create 8 in
  let raises =
    Paths.values
      [
        [ "Stdlib"; "raise" ];
        [ "Stdlib"; "raise_notrace" ];
        [ "Printexc"; "raise_with_backtrace" ];
        [ "Stdlib"; "Printexc"; "raise_with_backtrace" ];
      ]
  in
  let cancelled =
    try
      let initial = Lazy.force Env.initial in
      let description, _ =
        Env.lookup_constructor ~use:false ~loc:Location.none Env.Pattern
          (Paths.lid [ "Eio"; "Cancel"; "Cancelled" ])
          initial
      in
      match description.Data_types.cstr_tag with
      | Types.Extension path -> Some (Env.normalize_value_path None initial path)
      | _ -> None
    with Not_found | Env.Error _ -> None
  in
  let rec origin en seen path =
    if List.exists (Path.same path) seen then path
    else
      match Path.Tbl.find_opt rebindings path with
      | Some target -> origin en (path :: seen) target
      | None -> Env.normalize_value_path None (Paths.env en) path
  in
  let rec is_cancelled (p : pattern) =
    match p.pat_desc with
    | Tpat_alias { pattern; _ } -> is_cancelled pattern
    | Tpat_construct (_, description, _, _, _) -> (
        match (description.cstr_tag, cancelled) with
        | Types.Extension path, Some target -> Path.same (origin p.pat_env [] path) target
        | _ -> false)
    | _ -> false
  in
  let binding (p : pattern) =
    match p.pat_desc with
    | Tpat_var { id; _ } | Tpat_alias { id; _ } -> Some id
    | _ -> None
  in
  let raises_binding id e =
    match e.exp_desc with
    | Texp_apply (fn, args, _, _, _) when Paths.is_value raises fn -> (
        match arguments args with
        | (_, { exp_desc = Texp_ident { path = Path.Pident actual; _ }; _ }) :: _ ->
            Ident.same actual id
        | _ -> false)
    | _ -> false
  in
  (* ^nlintc-du4v: cleanup before propagation is legitimate. Prove only the
     presence of an original-value re-raise, not propagation on every path. *)
  let raises_in id e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            if raises_binding id e then found := true;
            base.expr self e);
      }
    in
    iterator.expr iterator e;
    !found
  in
  (* ^nlintc-du4v: returning the original exception as data is propagation,
     even though following the caller is deliberately out of scope. *)
  let rec carries id e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident actual; _ } -> Ident.same actual id
    | Texp_tuple (fields, _) -> List.exists (fun (_, e) -> carries id e) fields
    | Texp_construct (_, _, _, fields, _) ->
        List.exists (fun (_, e) -> carries id e) fields
    | Texp_variant (_, Some (payload, _)) -> carries id payload
    | Texp_record { fields; _ } ->
        Array.exists
          (function _, _, Overridden (_, e) -> carries id e | _ -> false)
          fields
    | Texp_record_unboxed_product { fields; _ } ->
        Array.exists
          (function _, _, Overridden (_, e) -> carries id e | _ -> false)
          fields
    | Texp_sequence (_, _, last) | Texp_let (_, _, last) -> carries id last
    | Texp_ifthenelse (_, yes, Some no) -> carries id yes || carries id no
    | Texp_match (_, _, cases, _, _) ->
        List.exists (fun case -> carries id case.c_rhs) cases
    | Texp_try (body, cases, _) ->
        carries id body || List.exists (fun case -> carries id case.c_rhs) cases
    | _ -> false
  in
  let propagates id e = raises_in id e || carries id e in
  let check cases =
    let cancellation_passes = ref false in
    List.iter
      (fun case ->
        let p = case.c_lhs in
        if is_cancelled p then begin
          let passes =
            Option.fold ~none:false ~some:(fun id -> propagates id case.c_rhs) (binding p)
          in
          if Option.is_some (binding p) && not passes then emit p.pat_loc;
          if case.c_guard = None && passes then cancellation_passes := true
        end
        else if (not !cancellation_passes) && case.c_guard = None then
          match p.pat_desc with
          | Tpat_any -> emit p.pat_loc
          | Tpat_var { id; name = { txt = "exn" | "_exn"; _ }; _ }
            when not (propagates id case.c_rhs) ->
              emit p.pat_loc
          | _ -> ())
      cases
  in
  {
    base with
    extension_constructor =
      (fun self ext ->
        (match ext.ext_kind with
        | Text_rebind (path, _) ->
            Path.Tbl.replace rebindings (Path.Pident ext.ext_id) path
        | _ -> ());
        base.extension_constructor self ext);
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_try (_, cases, _) -> check cases
        | Texp_match (_, _, cases, _, _) ->
            let exceptions =
              List.filter_map
                (fun case ->
                  match case.c_lhs.pat_desc with
                  | Tpat_exception p -> Some { case with c_lhs = p }
                  | _ -> None)
                cases
            in
            check exceptions
        | _ -> ());
        base.expr self e);
  }

let identifiers predicate emit =
  {
    base with
    expr =
      (fun self e ->
        if predicate e then emit e.exp_loc;
        base.expr self e);
  }

let stdlib_lock emit =
  let modules =
    Paths.modules
      [
        [ "Stdlib"; "Mutex" ];
        [ "Stdlib"; "Condition" ];
        [ "Stdlib"; "Semaphore" ];
        [ "Mutex" ];
        [ "Condition" ];
        [ "Semaphore" ];
      ]
  in
  identifiers (Paths.in_module modules) emit

let obj_magic emit =
  let modules = Paths.modules [ [ "Stdlib"; "Obj" ] ] in
  identifiers
    (fun e ->
      match e.exp_desc with
      | Texp_ident { path; _ } ->
          String.starts_with ~prefix:"magic" (Path.last path) && Paths.in_module modules e
      | _ -> false)
    emit

let raw_concurrency emit =
  let fiber = Paths.modules [ [ "Eio"; "Fiber" ] ] in
  let fiber_list = Paths.modules [ [ "Eio"; "Fiber"; "List" ] ] in
  let switch = Paths.modules [ [ "Eio"; "Switch" ] ] in
  let mutex = Paths.modules [ [ "Eio"; "Mutex" ] ] in
  identifiers
    (fun e ->
      match e.exp_desc with
      | Texp_ident { path; _ } ->
          let name = Path.last path in
          Paths.in_module mutex e || Paths.in_module fiber_list e
          || Paths.in_module fiber e
             && (String.starts_with ~prefix:"fork" name
                || List.mem name [ "both"; "pair"; "all"; "any"; "first" ])
          || Paths.in_module switch e
             && (name = "run" || String.starts_with ~prefix:"on_release" name)
      | _ -> false)
    emit

let sleep_names =
  [
    [ "Eio"; "Time"; "sleep" ];
    [ "Eio"; "Time"; "sleep_until" ];
    [ "Eio"; "Time"; "Mono"; "sleep" ];
    [ "Eio"; "Time"; "Mono"; "sleep_until" ];
    [ "Eio"; "Time"; "Mono"; "sleep_span" ];
    [ "Eio"; "Time"; "Timeout"; "sleep" ];
    [ "Eio_unix"; "sleep" ];
    [ "Ox"; "Concurrent"; "sleep" ];
  ]

let suspending_names =
  sleep_names
  @ [
      [ "Eio"; "Fiber"; "yield" ];
      [ "Eio"; "Fiber"; "await_cancel" ];
      [ "Eio"; "Promise"; "await" ];
      [ "Eio"; "Promise"; "await_exn" ];
      [ "Eio"; "Mutex"; "lock" ];
      [ "Eio"; "Mutex"; "use_rw" ];
      [ "Eio"; "Mutex"; "use_ro" ];
      [ "Eio"; "Condition"; "await" ];
      [ "Eio"; "Condition"; "await_no_mutex" ];
      [ "Eio"; "Semaphore"; "acquire" ];
      [ "Eio"; "Stream"; "add" ];
      [ "Eio"; "Stream"; "take" ];
      [ "Eio"; "Flow"; "single_read" ];
      [ "Eio"; "Flow"; "read_exact" ];
      [ "Eio"; "Flow"; "write" ];
      [ "Eio"; "Flow"; "copy" ];
      [ "Eio"; "Flow"; "copy_string" ];
      [ "Eio"; "Buf_write"; "flush" ];
      [ "Eio"; "Process"; "await" ];
      [ "Eio"; "Process"; "await_exn" ];
      [ "Eio"; "Process"; "run" ];
      [ "Eio"; "Net"; "accept" ];
      [ "Eio"; "Net"; "connect" ];
      [ "Eio"; "Net"; "send" ];
      [ "Eio"; "Net"; "recv" ];
      [ "Eio_unix"; "await_readable" ];
      [ "Eio_unix"; "await_writable" ];
      [ "Eio_unix"; "run_in_systhread" ];
      [ "Ox"; "Channel"; "send" ];
      [ "Ox"; "Channel"; "receive" ];
      [ "Ox"; "Select"; "select" ];
      [ "Ox"; "Fiber"; "await" ];
      [ "Ox"; "Scope"; "run" ];
    ]

let suspending_finalizer emit =
  let suspend = Paths.values suspending_names in
  let finally = Paths.values [ [ "Stdlib"; "Fun"; "protect" ] ] in
  let protect = Paths.values [ [ "Eio"; "Cancel"; "protect" ] ] in
  let releases =
    Paths.values
      [ [ "Eio"; "Switch"; "on_release" ]; [ "Eio"; "Switch"; "on_release_cancellable" ] ]
  in
  let cleanup = ref false and protected = ref false in
  let scoped final protection f =
    let old = (!cleanup, !protected) in
    cleanup := final;
    protected := protection;
    Fun.protect
      ~finally:(fun () ->
        let a, b = old in
        cleanup := a;
        protected := b)
      f
  in
  {
    base with
    expr =
      (fun self e ->
        match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) ->
            if !cleanup && (not !protected) && Paths.is_value suspend fn then
              emit e.exp_loc;
            let is_finally = Paths.is_value finally fn in
            let is_protect = Paths.is_value protect fn || Paths.is_value releases fn in
            if is_finally || is_protect then begin
              self.expr self fn;
              List.iter
                (fun (label, arg) ->
                  match arg.exp_desc with
                  | Texp_function _
                    when (is_finally && label = Labelled "finally")
                         || (is_protect && label = Nolabel) ->
                      scoped true (is_protect || !protected) (fun () ->
                          self.expr self arg)
                  | _ -> self.expr self arg)
                (arguments args)
            end
            else base.expr self e
        | _ -> base.expr self e);
  }

let race_deadline emit =
  let races =
    Paths.values
      [
        [ "Ox"; "Concurrent"; "race" ];
        [ "Ox"; "Concurrent"; "race_first" ];
        [ "Eio"; "Fiber"; "any" ];
      ]
  in
  let sleeps = Paths.values sleep_names in
  let contains_sleep e =
    let found = ref false in
    let iterator =
      {
        base with
        expr =
          (fun self e ->
            (match e.exp_desc with
            | Texp_apply (fn, _, _, _, _) when Paths.is_value sleeps fn -> found := true
            | _ -> ());
            base.expr self e);
      }
    in
    iterator.expr iterator e;
    !found
  in
  {
    base with
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _)
          when Paths.is_value races fn
               && List.exists (fun (_, arg) -> contains_sleep arg) (arguments args) ->
            emit e.exp_loc
        | _ -> ());
        base.expr self e);
  }
