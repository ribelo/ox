(* ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-truth: typed selection, lexical defaults, shape and finite implementation evidence. *)
open Ocaml_common
open Ox_caps
open Typedtree

type value = {
  name : string;
  loc : Location.t;
  families : string list;
  behaviour : bool;
  cancel_safety : bool;
  documentation : string list;
}

let targets =
  [
    ( "switch",
      [ "Eio.Switch.t"; "Ox.Scope.t"; "Ox.Scope.fork"; "Ox__Scope.t"; "Ox__Scope.fork" ]
    );
    ("clock", [ "Eio.Time.clock"; "Eio.Time.Mono.t" ]);
    ( "flow/capability",
      [
        "Eio.Resource.t";
        "Eio.Flow.source";
        "Eio.Flow.sink";
        "Eio.Flow.two_way";
        "Eio.Path.t";
      ] );
    ("channel", [ "Eio.Stream.t"; "Ox.Channel.t"; "Ox__Channel.t" ]);
    ( "actor",
      [
        "Ox.Actor.t";
        "Ox__Actor.t";
        "Ox.Actor.Changes.t";
        "Ox__Actor.Changes.t";
        "Ox.Agent.t";
        "Ox__Agent.t";
      ] );
    ("mutex", [ "Eio.Mutex.t" ]);
    ( "pool",
      [ "Eio.Pool.t"; "Ox_blocking.Pool.t"; "Ox_sql.Pool.runner"; "Ox_sql__Pool.runner" ]
    );
  ]
  @ [
      ( "capability",
        List.concat_map
          (fun name -> [ "Ox_caps.Cap.Token." ^ name; "Ox_caps_door." ^ name ])
          [
            "fork";
            "exec";
            "exit";
            "chdir";
            "env";
            "signal";
            "time";
            "random";
            "stdin";
            "stdout";
            "stderr";
            "fs_read";
            "fs_write";
            "tmp";
            "network";
            "process";
          ] );
    ]

let origins ~(caps : < Cap.fs_read ; .. >) () =
  ignore caps#fs_read;
  let initial = Lazy.force Env.initial in
  List.concat_map
    (fun (family, names) ->
      List.filter_map
        (fun name ->
          try
            let path, declaration =
              Env.lookup_type ~use:false ~loc:Location.none
                (Paths.lid (String.split_on_char '.' name))
                initial
            in
            Some
              ( family,
                Env.normalize_type_path None initial path,
                declaration.Types.type_uid )
          with Not_found | Env.Error _ -> None)
        names)
    targets

let selected ~(caps : < Cap.fs_read ; .. >) origins en ty =
  ignore caps#fs_read;
  let seen = Hashtbl.create 32 in
  let declarations = ref [] in
  let families = ref [] in
  let rec visit ty =
    let id = Types.get_id ty in
    if not (Hashtbl.mem seen id) then begin
      Hashtbl.add seen id ();
      (match Types.get_desc ty with
      | Tconstr (path, _, _) ->
          let declaration = Env.find_type path en in
          let normalized = Env.normalize_type_path None en path in
          List.iter
            (fun (family, origin, uid) ->
              if Path.same normalized origin || declaration.Types.type_uid = uid then
                families := family :: !families)
            origins;
          if not (List.exists (Path.same normalized) !declarations) then begin
            declarations := normalized :: !declarations;
            Option.iter visit declaration.type_manifest;
            Btype.iter_type_expr_kind visit declaration.type_kind
          end
      | _ -> ());
      Btype.iter_type_expr visit ty
    end
  in
  visit ty;
  List.sort_uniq String.compare !families

let normalize text =
  String.split_on_char ' '
    (String.map (function '\n' | '\r' | '\t' -> ' ' | c -> Char.lowercase_ascii c) text)
  |> List.filter (fun word -> word <> "")
  |> String.concat " "

let texts attributes =
  List.filter_map
    (fun (a : Parsetree.attribute) ->
      if a.attr_name.txt <> "ocaml.doc" && a.attr_name.txt <> "ocaml.text" then None
      else
        match a.attr_payload with
        | PStr
            [
              {
                pstr_desc =
                  Pstr_eval
                    ( {
                        pexp_desc =
                          Pexp_constant { pconst_desc = Pconst_string (s, _, _); _ };
                        _;
                      },
                      _ );
                _;
              };
            ] ->
            Some (normalize s)
        | _ -> None)
    attributes

let index text needle offset =
  let rec loop i =
    if i + String.length needle > String.length text then None
    else if String.sub text i (String.length needle) = needle then Some i
    else loop (i + 1)
  in
  loop offset

let labels =
  [ "suspension"; "cancellation"; "finalizers"; "locking"; "cancellation safety" ]

let fields texts =
  List.filter_map
    (fun label ->
      let marker = label ^ ":" in
      let hits =
        List.concat_map
          (fun text ->
            let rec loop offset =
              match index text marker offset with
              | None -> []
              | Some start ->
                  let header =
                    label = "finalizers" && start >= 17
                    && String.sub text (start - 17) 17 = "cancellation and "
                  in
                  let boundary = (not header) && (start = 0 || text.[start - 1] = ' ') in
                  let first = start + String.length marker in
                  let rec stop i =
                    if i >= String.length text then None
                    else if
                      text.[i] = '.' && (i + 1 = String.length text || text.[i + 1] = ' ')
                    then Some i
                    else stop (i + 1)
                  in
                  let sentence =
                    match stop first with
                    | None -> ""
                    | Some last ->
                        let value = String.trim (String.sub text first (last - first)) in
                        if
                          List.exists
                            (fun label -> Option.is_some (index value (label ^ ":") 0))
                            labels
                        then ""
                        else value
                  in
                  (if boundary then [ sentence ] else []) @ loop first
            in
            loop 0)
          texts
      in
      match hits with
      | [] -> None
      | [ value ] -> Some (label, value)
      | _ -> Some (label, ""))
    labels

let merge defaults own =
  let defaults =
    if List.mem_assoc "suspension" own || List.mem_assoc "cancellation" own then
      List.remove_assoc "cancellation safety" defaults
    else defaults
  in
  own @ List.filter (fun (label, _) -> not (List.mem_assoc label own)) defaults

let valid fields label prefixes =
  match List.assoc_opt label fields with
  | None -> false
  | Some value ->
      value <> ""
      && (prefixes = []
         || List.exists
              (fun prefix ->
                value = prefix
                || List.exists
                     (fun separator ->
                       String.starts_with ~prefix:(prefix ^ separator) value)
                     [ " "; ":"; ";"; "," ])
              prefixes)

let checks fields =
  let no_suspend = valid fields "suspension" [ "never suspends" ] in
  let behaviour =
    valid fields "suspension" [ "never suspends"; "may suspend" ]
    && valid fields "cancellation"
         [
           "not a cancellation point";
           "propagates";
           "protected";
           "classified";
           "depends on";
         ]
    && valid fields "finalizers" [] && valid fields "locking" []
  in
  let cancel_safety =
    (no_suspend && valid fields "cancellation" [ "not a cancellation point" ])
    || valid fields "cancellation" [ "protected throughout" ]
    || valid fields "cancellation safety"
         [
           "safe to re-run";
           "unsafe because data is lost";
           "unsafe because progress is lost";
         ]
  in
  (behaviour, cancel_safety)

let iterator ~(caps : < Cap.fs_read ; .. >) inspect =
  let origins = origins ~caps () in
  let defaults = ref [] in
  let modules = ref [] in
  let base = Tast_iterator.default_iterator in
  let default_fields attrs =
    texts attrs
    |> List.filter (fun text ->
        Option.is_some (index text "cancellation and finalizers:" 0))
    |> fields
  in
  {
    base with
    structure = (fun _ _ -> ());
    module_declaration =
      (fun self md ->
        let previous, parent = (!defaults, !modules) in
        defaults := merge !defaults (default_fields md.md_attributes);
        modules := !modules @ [ Option.value md.md_name.txt ~default:"_" ];
        base.module_declaration self md;
        defaults := previous;
        modules := parent);
    module_type_declaration =
      (fun self md ->
        let previous, parent = (!defaults, !modules) in
        defaults := merge !defaults (default_fields md.mtd_attributes);
        modules := !modules @ [ md.mtd_name.txt ];
        base.module_type_declaration self md;
        defaults := previous;
        modules := parent);
    signature =
      (fun self signature ->
        let previous = !defaults in
        let attributes =
          List.filter_map
            (fun item ->
              match item.sig_desc with Tsig_attribute a -> Some a | _ -> None)
            signature.sig_items
        in
        (* The parser may attach a leading module paragraph to its first declaration. *)
        let leading =
          match signature.sig_items with
          | { sig_desc = Tsig_value v; _ } :: _ -> v.val_attributes
          | { sig_desc = Tsig_type (_, t :: _); _ } :: _ -> t.typ_attributes
          | { sig_desc = Tsig_module m; _ } :: _ -> m.md_attributes
          | { sig_desc = Tsig_modtype m; _ } :: _ -> m.mtd_attributes
          | _ -> []
        in
        defaults := merge !defaults (default_fields (attributes @ leading));
        base.signature self signature;
        defaults := previous);
    signature_item =
      (fun self item ->
        (match item.sig_desc with
        | Tsig_value value ->
            let en = Paths.env ~caps item.sig_env in
            let families = selected ~caps origins en value.val_desc.ctyp_type in
            let behaviour, cancel_safety =
              checks (merge !defaults (fields (texts value.val_attributes)))
            in
            inspect
              {
                name = String.concat "." (!modules @ [ value.val_name.txt ]);
                loc = value.val_loc;
                families;
                behaviour;
                cancel_safety;
                documentation =
                  texts value.val_attributes
                  @ List.map
                      (fun (label, sentence) -> label ^ ": " ^ sentence ^ ".")
                      (let own = fields (texts value.val_attributes) in
                       List.filter
                         (fun (label, _) -> not (List.mem_assoc label own))
                         !defaults);
              }
        | _ -> ());
        base.signature_item self item);
  }

let behaviour ~(caps : < Cap.fs_read ; .. >) emit =
  iterator ~caps (fun value ->
      if value.families <> [] && not value.behaviour then emit value.loc)

let cancel_safety ~(caps : < Cap.fs_read ; .. >) emit =
  iterator ~caps (fun value ->
      if value.families <> [] && not value.cancel_safety then emit value.loc)

(* ^nlintd-truth ^nlintd-raises: a finite graph of effects, never recursive AST expansion. *)
module Names = Set.Make (String)

type effects = {
  suspension : Names.t;
  cancellation : Names.t;
  check_reachability : Names.t;
  exceptions : Names.t;
  explicit_raises : Names.t;
  opaque : Names.t;
}

type transformation = Filter of Names.t * bool | Wrap of string
type edge = { target : string; filters : transformation list }
type summary = { effects : effects; calls : edge list }
type definition = { body : expression; unit_name : string; mutable summary : summary }

module Expressions = Hashtbl.Make (struct
  type t = expression

  let equal a b = a == b
  let hash e = Hashtbl.hash e.exp_loc
end)

type evidence = {
  expressions : summary Expressions.t;
  definitions : (string, definition) Hashtbl.t;
  exports : (string, string) Hashtbl.t;
  resolved : (string, effects) Hashtbl.t;
}

let empty_effects =
  {
    suspension = Names.empty;
    cancellation = Names.empty;
    check_reachability = Names.empty;
    exceptions = Names.empty;
    explicit_raises = Names.empty;
    opaque = Names.empty;
  }

let empty_summary = { effects = empty_effects; calls = [] }

let union a b =
  {
    suspension = Names.union a.suspension b.suspension;
    cancellation = Names.union a.cancellation b.cancellation;
    check_reachability = Names.union a.check_reachability b.check_reachability;
    exceptions = Names.union a.exceptions b.exceptions;
    explicit_raises = Names.union a.explicit_raises b.explicit_raises;
    opaque = Names.union a.opaque b.opaque;
  }

let join a b = { effects = union a.effects b.effects; calls = a.calls @ b.calls }
let joins xs = List.fold_left join empty_summary xs

let unknown name =
  { empty_summary with effects = { empty_effects with opaque = Names.singleton name } }

let thrown name =
  {
    empty_summary with
    effects =
      {
        empty_effects with
        exceptions = Names.singleton name;
        explicit_raises = Names.singleton name;
      };
  }

let cancelled = "Eio.Cancel.Cancelled"

let filter_effects handled protected effects =
  let unhandled xs =
    if Names.mem "*" handled then Names.empty else Names.diff xs handled
  in
  let explicit_raises = unhandled effects.explicit_raises in
  {
    effects with
    explicit_raises;
    cancellation = (if protected then Names.empty else effects.cancellation);
    exceptions =
      ( unhandled effects.exceptions |> fun xs ->
        if protected then Names.union explicit_raises (Names.remove cancelled xs) else xs
      );
  }

let transform transformation effects =
  match transformation with
  | Filter (handled, protected) -> filter_effects handled protected effects
  | Wrap name ->
      if Names.is_empty effects.exceptions then effects
      else
        {
          effects with
          exceptions = Names.singleton name;
          explicit_raises = Names.singleton name;
        }

let apply_filters filters effects =
  List.fold_left (fun effects filter -> transform filter effects) effects filters

let transformed transformation summary =
  {
    effects = transform transformation summary.effects;
    calls =
      List.map
        (fun edge -> { edge with filters = edge.filters @ [ transformation ] })
        summary.calls;
  }

let under handled protected summary = transformed (Filter (handled, protected)) summary
let wrapped name summary = transformed (Wrap name) summary
let local_key unit_name id = unit_name ^ ":" ^ Ident.unique_name id

let arguments args =
  List.filter_map (function label, Arg (e, _) -> Some (label, e) | _ -> None) args

let contains text needle = Option.is_some (index text (String.lowercase_ascii needle) 0)

(* These are semantic leaves, resolved through compiler paths (including aliases), not
   spelling tests. Other external values remain opaque. Each leaf's suspension/check
   distinction follows Eio's implementation; an on_release hook is deferred. *)
let semantic_leaves =
  [
    ("Eio.Fiber.yield", true, true, []);
    ("Eio.Fiber.await_cancel", true, true, []);
    ("Eio.Promise.await", true, true, []);
    ("Eio.Promise.await_exn", true, true, []);
    ("Eio.Stream.add", true, true, []);
    ("Eio.Stream.take", true, true, []);
    ("Eio.Condition.await", true, true, []);
    ("Eio.Mutex.lock", true, true, []);
    ("Eio.Semaphore.acquire", true, true, []);
    ("Eio.Time.sleep", true, true, []);
    ("Eio.Time.Mono.sleep", true, true, []);
    ("Eio.Time.Mono.sleep_until", true, true, []);
    ("Eio.Switch.check", false, true, [ "Invalid_argument" ]);
    ("Eio.Cancel.check", false, true, [ "Invalid_argument" ]);
    ("Eio.Switch.on_release", false, false, [ "Invalid_argument" ]);
    ("Eio.Switch.on_release_cancellable", false, false, [ "Invalid_argument" ]);
  ]

let special_names =
  [
    "Stdlib.raise";
    "Stdlib.raise_notrace";
    "Printexc.raise_with_backtrace";
    "Stdlib.invalid_arg";
    "Stdlib.failwith";
    "Fun.protect";
    "Eio.Cancel.protect";
    "Eio.Switch.on_release";
    "Eio.Switch.on_release_cancellable";
  ]

let leaf_origins ~caps =
  List.filter_map
    (fun (name, suspension, cancellation, exceptions) ->
      Option.map
        (fun path -> (Path.name path, (name, suspension, cancellation, exceptions)))
        (Paths.value ~caps (String.split_on_char '.' name)))
    semantic_leaves

let special_origins ~caps =
  List.filter_map
    (fun name ->
      let explicit =
        if List.mem name [ "Fun.protect"; "Printexc.raise_with_backtrace" ] then
          "Stdlib." ^ name
        else name
      in
      Option.map
        (fun path -> (Path.name path, name))
        (Paths.value ~caps (String.split_on_char '.' explicit)))
    special_names

let exception_name description =
  match description.Data_types.cstr_tag with
  | Types.Extension path -> Path.name path
  | _ -> description.cstr_name

let canonical_exception name =
  if String.ends_with ~suffix:".Cancelled" name then cancelled
  else if String.ends_with ~suffix:".Release_error" name then "Eio.Switch.Release_error"
  else if String.ends_with ~suffix:".Finally_raised" name then "Fun.Finally_raised"
  else
    match List.rev (String.split_on_char '.' name) with
    | (("Invalid_argument" | "Failure" | "Assert_failure" | "Match_failure") as name) :: _
      ->
        name
    | _ -> name

let known_exception e =
  match e.exp_desc with
  | Texp_construct (_, description, _, _, _) ->
      Some (canonical_exception (exception_name description))
  | _ -> None

let primitive_is_pure description =
  match description.Types.val_kind with
  | Val_prim primitive ->
      List.mem primitive.Primitive.prim_name
        [
          "%identity";
          "%ignore";
          "%intadd";
          "%intsub";
          "%intmul";
          "%intand";
          "%intor";
          "%intxor";
          "%intlsl";
          "%intlsr";
          "%intasr";
          "%intneg";
          "%eq";
          "%noteq";
          "%boolnot";
          "%sequand";
          "%sequor";
          "%makemutable";
          "%field0";
          "%field1";
          "%setfield0";
        ]
  | _ -> false

let rec function_body e =
  match e.exp_desc with
  | Texp_function { body = Tfunction_body body; _ } -> function_body body
  | _ -> e

let add_unit ~caps evidence artifact =
  Artifact.setup ~caps artifact;
  let unit_name = Compilation_unit.name_as_string artifact.Artifact.info.cmt_modname in
  let leaves, specials = (leaf_origins ~caps, special_origins ~caps) in
  let rec named_path = function
    | Path.Pident id when not (Ident.is_global_or_predef id) -> local_key unit_name id
    | Path.Pdot (parent, name) -> named_path parent ^ "." ^ name
    | path -> Path.name path
  in
  let key e path =
    match path with
    | Path.Pident id when not (Ident.is_global_or_predef id) -> local_key unit_name id
    | _ -> named_path (Env.normalize_value_path None (Paths.env ~caps e.exp_env) path)
  in
  let origin e =
    match e.exp_desc with
    | Texp_ident { path; _ } -> key e path
    | _ -> "indirect call at " ^ string_of_int e.exp_loc.loc_start.pos_lnum
  in
  let special e = List.assoc_opt (origin e) specials in
  let base = Tast_iterator.default_iterator in
  let modules = ref [] in
  let module_identity = ref None in
  let declare ~export vb =
    List.iter
      (fun id ->
        let name = local_key unit_name id in
        if not (Hashtbl.mem evidence.definitions name) then
          Hashtbl.add evidence.definitions name
            { body = vb.vb_expr; unit_name; summary = empty_summary };
        if export then begin
          Hashtbl.replace evidence.exports
            (String.concat "." ((unit_name :: !modules) @ [ Ident.name id ]))
            name;
          Option.iter
            (fun parent ->
              Hashtbl.replace evidence.exports (parent ^ "." ^ Ident.name id) name)
            !module_identity
        end)
      (Typedtree.pat_bound_idents vb.vb_pat)
  in
  let collect =
    {
      base with
      module_binding =
        (fun self binding ->
          let saved, saved_identity = (!modules, !module_identity) in
          let name = Option.value binding.mb_name.txt ~default:"_" in
          modules := !modules @ [ name ];
          module_identity :=
            Some
              (match (!module_identity, binding.mb_id) with
              | None, Some id -> local_key unit_name id
              | Some parent, _ -> parent ^ "." ^ name
              | _ -> unit_name ^ "." ^ name);
          base.module_binding self binding;
          modules := saved;
          module_identity := saved_identity);
      structure_item =
        (fun self item ->
          (match item.str_desc with
          | Tstr_value (_, bindings) -> List.iter (declare ~export:true) bindings
          | _ -> ());
          base.structure_item self item);
      value_binding =
        (fun self vb ->
          declare ~export:false vb;
          base.value_binding self vb);
    }
  in
  (match artifact.info.cmt_annots with
  | Implementation tree -> collect.structure collect tree
  | _ -> ());
  let rec unrestricted : pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> unrestricted pattern
    | Tpat_or (a, b, _) -> unrestricted a || unrestricted b
    | _ -> false
  in
  let rec pattern_exception : pattern -> Names.t =
   fun p ->
    match p.pat_desc with
    | Tpat_construct (_, description, _, args, _)
      when List.for_all (fun (_, p) -> unrestricted p) args ->
        Names.singleton (canonical_exception (exception_name description))
    | Tpat_alias { pattern; _ } -> pattern_exception pattern
    | Tpat_or (a, b, _) -> Names.union (pattern_exception a) (pattern_exception b)
    | Tpat_any | Tpat_var _ -> Names.singleton "*"
    | _ -> Names.empty
  in
  let function_typed e =
    match Types.get_desc e.exp_type with Tarrow _ -> true | _ -> false
  in
  let pure_callee e =
    match e.exp_desc with Texp_ident { desc; _ } -> primitive_is_pure desc | _ -> false
  in
  let rec invokes e =
    match e.exp_desc with
    | Texp_function { body = Tfunction_body body; _ } -> invokes body
    | Texp_function { body = Tfunction_cases cases; _ } ->
        joins
          (List.map
             (fun c ->
               joins (List.map expression (Option.to_list c.c_guard @ [ c.c_rhs ])))
             cases.fc_cases)
    | Texp_ident { path; desc; _ } ->
        if primitive_is_pure desc then empty_summary
        else { empty_summary with calls = [ { target = key e path; filters = [] } ] }
    | Texp_apply (callee, _, _, _, _) when function_typed e ->
        join (expression e) (unknown ("returned-function callback from " ^ origin callee))
    | _ -> expression e
  and expression e =
    match Expressions.find_opt evidence.expressions e with
    | Some summary -> summary
    | None ->
        let summary = describe e in
        Expressions.add evidence.expressions e summary;
        summary
  and describe e =
    match e.exp_desc with
    | Texp_function _ -> empty_summary
    | Texp_apply (callee, args, _, _, _) ->
        let args = arguments args in
        let evaluated =
          joins (expression callee :: List.map (fun (_, e) -> expression e) args)
        in
        let call =
          match special callee with
          | Some
              ("Stdlib.raise" | "Stdlib.raise_notrace" | "Printexc.raise_with_backtrace")
            -> (
              match args with
              | (_, ex) :: _ -> (
                  match known_exception ex with
                  | Some name -> thrown name
                  | None -> unknown "dynamic exception re-raise")
              | [] -> unknown "raise without exception evidence")
          | Some "Stdlib.invalid_arg" -> thrown "Invalid_argument"
          | Some "Stdlib.failwith" -> thrown "Failure"
          | Some "Eio.Cancel.protect" ->
              joins (List.map (fun (_, e) -> under Names.empty true (invokes e)) args)
          | Some "Fun.protect" ->
              joins
                (List.map
                   (fun (label, e) ->
                     let callback = invokes e in
                     if label = Typedtree.Labelled "finally" then
                       wrapped "Fun.Finally_raised" callback
                     else callback)
                   args)
          | Some ("Eio.Switch.on_release" | "Eio.Switch.on_release_cancellable") ->
              let callbacks =
                match List.rev args with
                | (_, callback) :: _ -> under Names.empty true (invokes callback)
                | [] -> unknown "Eio.Switch.on_release callback"
              in
              join (thrown "Invalid_argument")
                (wrapped "Eio.Switch.Release_error" callbacks)
          | _ -> (
              match List.assoc_opt (origin callee) leaves with
              | Some (name, suspends, checks, exceptions) ->
                  let summary =
                    {
                      empty_summary with
                      effects =
                        {
                          empty_effects with
                          suspension =
                            (if suspends then Names.singleton name else Names.empty);
                          cancellation =
                            (if checks then Names.singleton name else Names.empty);
                          check_reachability =
                            (if checks then Names.singleton name else Names.empty);
                          exceptions =
                            Names.of_list
                              (exceptions @ if checks then [ cancelled ] else []);
                        };
                    }
                  in
                  if name = "Eio.Promise.await_exn" then
                    join summary (unknown (name ^ " stored exception"))
                  else summary
              | None when pure_callee callee -> invokes callee
              | None ->
                  let callbacks =
                    joins
                      (List.filter_map
                         (fun (_, arg) ->
                           if function_typed arg then
                             Some (unknown ("callback argument to " ^ origin callee))
                           else None)
                         args)
                  in
                  let invocation =
                    if function_typed e then
                      unknown (origin callee ^ " partial application")
                    else invokes callee
                  in
                  join invocation callbacks)
        in
        join evaluated call
    | Texp_ident _ | Texp_constant _ -> empty_summary
    | Texp_let (_, bindings, body) ->
        joins
          (expression body
          :: List.map
               (fun vb ->
                 match vb.vb_expr.exp_desc with
                 | Texp_function _ -> empty_summary
                 | Texp_ident { path; _ } ->
                     (* An alias is not executed here. Its definition is followed when invoked. *)
                     if Hashtbl.mem evidence.definitions (key vb.vb_expr path) then
                       empty_summary
                     else expression vb.vb_expr
                 | _ -> expression vb.vb_expr)
               bindings)
    | Texp_try (body, cases, _) ->
        let caught =
          List.fold_left
            (fun caught c ->
              if c.c_guard <> None then caught
              else Names.union caught (pattern_exception c.c_lhs))
            Names.empty cases
        in
        join
          (under caught false (expression body))
          (joins
             (List.map
                (fun c ->
                  joins (List.map expression (Option.to_list c.c_guard @ [ c.c_rhs ])))
                cases))
    | Texp_match (body, _, cases, _, _) ->
        let caught =
          List.fold_left
            (fun caught c ->
              if c.c_guard <> None then caught
              else
                match snd (Typedtree.split_pattern c.c_lhs) with
                | None -> caught
                | Some pattern -> Names.union caught (pattern_exception pattern))
            Names.empty cases
        in
        join
          (under caught false (expression body))
          (joins
             (List.map
                (fun c ->
                  joins (List.map expression (Option.to_list c.c_guard @ [ c.c_rhs ])))
                cases))
    | Texp_assert (condition, _) ->
        let proven =
          match condition.exp_desc with
          | Texp_construct (_, description, _, [], _) -> description.cstr_name = "true"
          | _ -> false
        in
        join (expression condition)
          (if proven then empty_summary else thrown "Assert_failure")
    | Texp_ifthenelse (condition, yes, no) ->
        let branches =
          match condition.exp_desc with
          | Texp_construct (_, description, _, [], _) when description.cstr_name = "true"
            ->
              expression yes
          | Texp_construct (_, description, _, [], _) when description.cstr_name = "false"
            ->
              joins (List.map expression (Option.to_list no))
          | _ -> joins (expression yes :: List.map expression (Option.to_list no))
        in
        join (expression condition) branches
    | Texp_send _ -> children (unknown "object method dispatch") e
    | Texp_letop _ -> children (unknown "let-operator invocation") e
    | _ -> children empty_summary e
  and children initial e =
    let result = ref initial in
    let walk =
      { base with expr = (fun _ child -> result := join !result (expression child)) }
    in
    base.expr walk e;
    !result
  in
  Hashtbl.iter
    (fun _ definition ->
      if definition.unit_name = unit_name then
        definition.summary <-
          (match definition.body.exp_desc with
          | Texp_ident _ -> invokes definition.body
          | _ -> invokes definition.body))
    evidence.definitions

let resolve evidence =
  let reverse = Hashtbl.create 128 in
  let target key = Option.value (Hashtbl.find_opt evidence.exports key) ~default:key in
  Hashtbl.iter
    (fun name definition ->
      let effects = ref definition.summary.effects in
      List.iter
        (fun edge ->
          let key = target edge.target in
          if Hashtbl.mem evidence.definitions key then
            Hashtbl.replace reverse key
              (name :: Option.value (Hashtbl.find_opt reverse key) ~default:[])
          else effects := union !effects (unknown edge.target).effects)
        definition.summary.calls;
      Hashtbl.replace evidence.resolved name !effects)
    evidence.definitions;
  let queue = Queue.create () in
  let queued = Hashtbl.create 128 in
  let enqueue name =
    if not (Hashtbl.mem queued name) then (
      Hashtbl.add queued name ();
      Queue.add name queue)
  in
  Hashtbl.iter (fun name _ -> enqueue name) evidence.definitions;
  while not (Queue.is_empty queue) do
    let name = Queue.take queue in
    Hashtbl.remove queued name;
    let definition = Hashtbl.find evidence.definitions name in
    let before = Hashtbl.find evidence.resolved name in
    let after =
      List.fold_left
        (fun effects edge ->
          match Hashtbl.find_opt evidence.resolved (target edge.target) with
          | None -> effects
          | Some callee -> union effects (apply_filters edge.filters callee))
        before definition.summary.calls
    in
    if
      not
        (Names.equal after.suspension before.suspension
        && Names.equal after.cancellation before.cancellation
        && Names.equal after.check_reachability before.check_reachability
        && Names.equal after.exceptions before.exceptions
        && Names.equal after.explicit_raises before.explicit_raises
        && Names.equal after.opaque before.opaque)
    then (
      Hashtbl.replace evidence.resolved name after;
      List.iter enqueue (Option.value (Hashtbl.find_opt reverse name) ~default:[]))
  done

let evidence_cache = Hashtbl.create 16

let package_evidence ~caps (implementation : Artifact.t) =
  let directory = Filename.dirname implementation.Artifact.path in
  match Hashtbl.find_opt evidence_cache directory with
  | Some evidence -> evidence
  | None ->
      let evidence =
        {
          expressions = Expressions.create 1024;
          definitions = Hashtbl.create 128;
          exports = Hashtbl.create 128;
          resolved = Hashtbl.create 128;
        }
      in
      Cap_sys.readdir ~caps directory
      |> Array.to_list |> List.sort String.compare
      |> List.filter (fun name -> Filename.check_suffix name ".cmt")
      |> List.iter (fun name ->
          let artifact = Artifact.read ~caps (Filename.concat directory name) in
          (* Use the original source, not merely the annotation's build copy. *)
          let build_source = Artifact.source artifact in
          let marker = "/_build/default/" in
          if Filename.check_suffix build_source ".ml-gen" then begin
            let alias_module binding =
              match binding.mb_expr.mod_desc with Tmod_ident _ -> true | _ -> false
            in
            let aliases_only =
              match artifact.info.cmt_annots with
              | Implementation tree ->
                  List.for_all
                    (fun item ->
                      match item.str_desc with
                      | Tstr_module binding -> alias_module binding
                      | Tstr_attribute _ -> true
                      | _ -> false)
                    tree.str_items
              | _ -> false
            in
            if not aliases_only then
              failwith (artifact.path ^ ": generated wrapper is not alias-only")
            (* Dune's alias-only wrappers contain no executable definitions. Canonical
               compiler paths resolve their exports to the actual compilation unit. *)
          end
          else begin
            let source =
              match index build_source marker 0 with
              | Some i ->
                  Filename.concat (String.sub build_source 0 i)
                    (String.sub build_source
                       (i + String.length marker)
                       (String.length build_source - i - String.length marker))
              | None -> build_source
            in
            let source =
              if Filename.check_suffix source ".pp.ml" then
                Filename.chop_suffix source ".pp.ml" ^ ".ml"
              else source
            in
            Artifact.check ~caps ~source artifact;
            add_unit ~caps evidence artifact
          end);
      resolve evidence;
      Hashtbl.add evidence_cache directory evidence;
      evidence

let raises_tags docs =
  List.concat_map
    (fun text ->
      let rec loop offset =
        match index text "@raise " offset with
        | None -> []
        | Some i ->
            let start = i + 7 in
            let stop =
              Option.value
                (String.index_from_opt text start ' ')
                ~default:(String.length text)
            in
            String.sub text start (stop - start) :: loop stop
      in
      loop 0)
    docs
  |> List.sort_uniq String.compare

let exception_mentioned docs name =
  let name = String.lowercase_ascii name in
  let short = List.hd (List.rev (String.split_on_char '.' name)) in
  List.exists (fun text -> contains text name || contains text short) docs

let opaque_qualified docs target =
  let target = String.lowercase_ascii target in
  let module_name = List.hd (String.split_on_char '.' target) in
  let module_name =
    match index module_name "__" 0 with
    | Some i -> String.sub module_name 0 i
    | None -> module_name
  in
  List.exists
    (fun text ->
      (contains text "depends on" || contains text "depend on" || contains text "delegat"
     || contains text "outside" || contains text "not checked")
      &&
      if
        contains target "callback argument to"
        || contains target "returned-function callback"
      then contains text "callback" || contains text "caller code"
      else
        contains text target || contains text module_name
        || (contains text "callback" || contains text "caller code"
          || contains text "hook"
           || contains text "functor argument"
           || contains text "module argument")
           && contains target ":"
        || (contains target "stored exception" && contains text "promise"))
    docs

(* ^nlintd-cleanup: cleanup requires a cancellation-path witness for the same resource.
   A success-only close, or a hook that merely mentions the handle, is not a witness. *)
let cleanup_obligations ~caps evidence definition =
  let unit_name = definition.unit_name in
  let specials = special_origins ~caps in
  let closes =
    Paths.values ~caps
      [
        [ "Stdlib"; "close_in" ];
        [ "Stdlib"; "close_out" ];
        [ "Stdlib"; "In_channel"; "close" ];
        [ "Stdlib"; "Out_channel"; "close" ];
        [ "Eio"; "Resource"; "close" ];
        [ "Eio"; "Flow"; "close" ];
      ]
  in
  let path e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } when not (Ident.is_global_or_predef id) ->
        local_key unit_name id
    | Texp_ident { path; _ } ->
        Path.name (Env.normalize_value_path None (Paths.env ~caps e.exp_env) path)
    | _ -> "indirect cleanup"
  in
  let expression_effects e =
    match Expressions.find_opt evidence.expressions e with
    | None ->
        { empty_effects with opaque = Names.singleton "unanalysed cleanup expression" }
    | Some summary ->
        List.fold_left
          (fun effects edge ->
            let key =
              Option.value
                (Hashtbl.find_opt evidence.exports edge.target)
                ~default:edge.target
            in
            match Hashtbl.find_opt evidence.resolved key with
            | Some effects' -> union effects (apply_filters edge.filters effects')
            | None -> union effects (unknown edge.target).effects)
          summary.effects summary.calls
  in
  let argument id args =
    List.exists
      (fun (_, e) ->
        match e.exp_desc with
        | Texp_ident { path = Path.Pident actual; _ } -> Ident.same id actual
        | _ -> false)
      (arguments args)
  in
  let direct_close id e =
    match e.exp_desc with
    | Texp_apply (callee, args, _, _, _) ->
        argument id args
        && List.exists (fun origin -> Path.name origin = path callee) closes
    | _ -> false
  in
  let safe_before protected e =
    let effects = filter_effects Names.empty protected (expression_effects e) in
    if not (Names.is_empty effects.opaque) then `Unknown
    else if not (Names.is_empty effects.exceptions) then `Missing
    else `Clean
  in
  let rec finalizer protected id e =
    match e.exp_desc with
    | Texp_function { body = Tfunction_body body; _ } -> finalizer protected id body
    | Texp_function _ | Texp_ident _ -> `Unknown
    | Texp_sequence (first, _, rest) -> (
        match finalizer protected id first with
        | `Clean -> `Clean
        | `Unknown -> `Unknown
        | `Missing -> (
            match safe_before protected first with
            | `Clean -> finalizer protected id rest
            | other -> other))
    | Texp_let (_, bindings, body) ->
        let before = List.map (fun b -> safe_before protected b.vb_expr) bindings in
        if List.mem `Unknown before then `Unknown
        else if List.mem `Missing before then `Missing
        else finalizer protected id body
    | Texp_ifthenelse (condition, yes, Some no) -> (
        match safe_before protected condition with
        | `Clean -> (
            match (finalizer protected id yes, finalizer protected id no) with
            | `Clean, `Clean -> `Clean
            | `Unknown, _ | _, `Unknown -> `Unknown
            | _ -> `Missing)
        | other -> other)
    | Texp_apply (callee, args, _, _, _)
      when List.assoc_opt (path callee) specials = Some "Eio.Cancel.protect" -> (
        match List.rev (arguments args) with
        | (_, callback) :: _ -> finalizer true id callback
        | [] -> `Unknown)
    | _ when direct_close id e -> `Clean
    | _ -> (
        if not (Names.is_empty (expression_effects e).opaque) then `Unknown
        else
          match Expressions.find_opt evidence.expressions e with
          | Some summary when summary.calls <> [] -> `Unknown
          | _ -> `Missing)
  in
  let registered id e =
    match e.exp_desc with
    | Texp_apply (callee, args, _, _, _)
      when List.mem
             (List.assoc_opt (path callee) specials)
             [ Some "Eio.Switch.on_release"; Some "Eio.Switch.on_release_cancellable" ]
      -> (
        match List.rev (arguments args) with
        | (_, callback) :: _ -> finalizer true id callback
        | [] -> `Unknown)
    | _ -> `Missing
  in
  let acquisitions =
    Paths.values ~caps
      (List.map (String.split_on_char '.')
         [
           "Stdlib.open_in";
           "Stdlib.open_out";
           "Stdlib.open_in_bin";
           "Stdlib.open_out_bin";
           "Stdlib.open_in_gen";
           "Stdlib.open_out_gen";
           "Stdlib.In_channel.open_bin";
           "Stdlib.In_channel.open_text";
           "Stdlib.Out_channel.open_bin";
           "Stdlib.Out_channel.open_text";
           "Ox_caps.Cap_stdlib.open_in";
           "Ox_caps.Cap_stdlib.open_out";
           "Ox_caps.Cap_stdlib.open_in_bin";
           "Ox_caps.Cap_stdlib.open_out_bin";
           "Ox_caps.Cap_stdlib.open_in_gen";
           "Ox_caps.Cap_stdlib.open_out_gen";
           "Eio.Path.open_in";
           "Eio.Path.open_out";
           "Eio.Path.open_rw";
           "Eio.Path.open_dir";
           "Eio.Net.connect";
           "Eio.Net.accept";
         ])
  in
  let switch_owned =
    Paths.values ~caps
      (List.map (String.split_on_char '.')
         [
           "Eio.Path.open_in";
           "Eio.Path.open_out";
           "Eio.Path.open_rw";
           "Eio.Path.open_dir";
           "Eio.Net.connect";
           "Eio.Net.accept";
         ])
  in
  let initially_owned e =
    match e.exp_desc with
    | Texp_apply (callee, _, _, _, _) ->
        List.exists (fun origin -> Path.name origin = path callee) switch_owned
    | _ -> false
  in
  let acquired e =
    match e.exp_desc with
    | Texp_apply (callee, _, _, _, _) ->
        List.exists (fun origin -> Path.name origin = path callee) acquisitions
    | _ -> false
  in
  let missing, opaque = (ref Names.empty, ref Names.empty) in
  let cancellation id owned e =
    if not owned then begin
      let effects = expression_effects e in
      if
        Names.mem cancelled effects.exceptions
        || not (Names.is_empty effects.cancellation)
      then missing := Names.add (Ident.name id) !missing
      else if not (Names.is_empty effects.opaque) then
        opaque := Names.add (Ident.name id) !opaque
    end
  in
  let rec any_payload : pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> any_payload pattern
    | _ -> false
  in
  let rec catches_cancel : pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> catches_cancel pattern
    | Tpat_or (a, b, _) -> catches_cancel a || catches_cancel b
    | Tpat_construct (_, description, _, args, _) ->
        canonical_exception (exception_name description) = cancelled
        && List.for_all (fun (_, p) -> any_payload p) args
    | _ -> false
  in
  let rec may_catch_cancel : pattern -> bool =
   fun p ->
    match p.pat_desc with
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> may_catch_cancel pattern
    | Tpat_or (a, b, _) -> may_catch_cancel a || may_catch_cancel b
    | Tpat_construct (_, description, _, _, _) ->
        canonical_exception (exception_name description) = cancelled
    | _ -> false
  in
  let rec scan id owned e =
    match e.exp_desc with
    | Texp_function _ -> owned
    | Texp_try (body, cases, _) ->
        let handlers = List.filter (fun c -> may_catch_cancel c.c_lhs) cases in
        if
          List.exists (fun c -> c.c_guard = None && catches_cancel c.c_lhs) handlers
          && List.for_all
               (fun c -> c.c_guard = None && finalizer false id c.c_rhs = `Clean)
               handlers
        then (
          ignore (scan id true body);
          owned)
        else if
          List.exists
            (fun c -> c.c_guard <> None || finalizer false id c.c_rhs = `Unknown)
            handlers
        then (
          opaque := Names.add (Ident.name id) !opaque;
          owned)
        else (
          cancellation id owned e;
          owned)
    | Texp_sequence (first, _, rest) -> scan id (scan id owned first) rest
    | Texp_let (_, bindings, body) ->
        let owned =
          List.fold_left
            (fun owned binding -> scan id owned binding.vb_expr)
            owned bindings
        in
        scan id owned body
    | Texp_ifthenelse (condition, yes, no) ->
        let owned = scan id owned condition in
        let yes = scan id owned yes in
        let no = Option.fold ~none:owned ~some:(scan id owned) no in
        yes && no
    | Texp_apply (callee, args, _, _, _)
      when List.assoc_opt (path callee) specials = Some "Fun.protect" ->
        let args = arguments args in
        let bracketed =
          List.exists
            (fun (label, callback) ->
              label = Typedtree.Labelled "finally" && finalizer false id callback = `Clean)
            args
        in
        if bracketed then owned
        else if
          List.exists
            (fun (label, callback) ->
              label = Typedtree.Labelled "finally"
              && finalizer false id callback = `Unknown)
            args
        then (
          opaque := Names.add (Ident.name id) !opaque;
          true)
        else (
          cancellation id owned e;
          owned)
    | _ when registered id e = `Clean || direct_close id e -> true
    | _ when registered id e = `Unknown ->
        opaque := Names.add (Ident.name id) !opaque;
        true
    | _ ->
        cancellation id owned e;
        owned
  in
  let base = Tast_iterator.default_iterator in
  let walk =
    {
      base with
      expr =
        (fun self e ->
          (match e.exp_desc with
          | Texp_let (_, bindings, body) ->
              List.iter
                (fun binding ->
                  if acquired binding.vb_expr then
                    List.iter
                      (fun id -> ignore (scan id (initially_owned binding.vb_expr) body))
                      (Typedtree.pat_bound_idents binding.vb_pat))
                bindings
          | _ -> ());
          base.expr self e);
    }
  in
  walk.expr walk (function_body definition.body);
  (Names.elements !missing, Names.elements !opaque)

let truth ~caps ~source ~artifact ~rules ~emit ~undecided =
  match artifact.Artifact.info.cmt_annots with
  | Interface tree -> (
      let selected_values = ref [] in
      let inspect value =
        if value.families <> [] then selected_values := value :: !selected_values
      in
      let walk = iterator ~caps inspect in
      walk.signature walk tree;
      if !selected_values <> [] then
        try
          let implementation_source = Filename.chop_suffix source ".mli" ^ ".ml" in
          let implementation = Artifact.find ~caps implementation_source in
          Artifact.check ~caps ~source:implementation_source implementation;
          let evidence = package_evidence ~caps implementation in
          Artifact.setup ~caps implementation;
          List.iter
            (fun value ->
              let qualified =
                Compilation_unit.name_as_string implementation.info.cmt_modname
                ^ "." ^ value.name
              in
              match Hashtbl.find_opt evidence.exports qualified with
              | None ->
                  undecided value.loc
                    (qualified
                   ^ ": implementation binding not visible (include, functor or abstract \
                      module)")
              | Some key ->
                  let effects = Hashtbl.find evidence.resolved key in
                  let docs = value.documentation in
                  let claims = fields docs in
                  let no_suspend = valid claims "suspension" [ "never suspends" ] in
                  let no_added =
                    List.exists
                      (fun text ->
                        List.exists (contains text)
                          [
                            "adds no eio operation";
                            "no added eio operation";
                            "no additional eio operation";
                            "adds no cancellation check";
                            "no additional cancellation check";
                          ])
                      docs
                  in
                  let no_check =
                    valid claims "cancellation" [ "not a cancellation point" ] || no_added
                  in
                  let report rule message =
                    if List.mem rule rules then
                      emit rule value.loc (qualified ^ ": " ^ message)
                  in
                  if (no_suspend || no_added) && not (Names.is_empty effects.suspension)
                  then
                    report "ox-val-behaviour"
                      ("documented never suspends; reaches "
                      ^ String.concat ", " (Names.elements effects.suspension));
                  let checks =
                    if no_added then effects.check_reachability else effects.cancellation
                  in
                  if no_check && not (Names.is_empty checks) then
                    report "ox-val-behaviour"
                      ((if no_added then
                          "documented no added Eio operation/check; reaches "
                        else "documented no cancellation point; reaches ")
                      ^ String.concat ", " (Names.elements checks));
                  Names.iter
                    (fun name ->
                      if not (exception_mentioned docs name) then
                        report "ox-val-behaviour"
                          ("reachable raise not documented: " ^ name))
                    effects.exceptions;
                  List.iter
                    (fun tag ->
                      if
                        not
                          (Names.exists
                             (fun name ->
                               String.lowercase_ascii name = tag
                               || String.lowercase_ascii
                                    (List.hd (List.rev (String.split_on_char '.' name)))
                                  = tag)
                             effects.exceptions)
                      then
                        if Names.is_empty effects.opaque then
                          report "ox-val-behaviour"
                            ("@raise " ^ tag ^ " has no reachable raise")
                        else
                          undecided value.loc
                            (qualified ^ ": @raise " ^ tag
                           ^ " cannot be established through opaque calls"))
                    (raises_tags docs);
                  let relevant =
                    List.filter_map
                      (fun label -> List.assoc_opt label claims)
                      [ "suspension"; "cancellation" ]
                  in
                  Names.iter
                    (fun target ->
                      let bounded =
                        opaque_qualified docs target
                        && ((not no_suspend)
                           || opaque_qualified
                                (Option.to_list (List.assoc_opt "suspension" claims))
                                target)
                        && ((not no_check)
                           || opaque_qualified
                                (Option.to_list (List.assoc_opt "cancellation" claims))
                                target)
                        && (relevant = []
                           || opaque_qualified relevant target
                           || List.exists
                                (fun doc ->
                                  (contains doc "exception" || contains doc "raise")
                                  && opaque_qualified [ doc ] target)
                                docs)
                      in
                      if not bounded then
                        undecided value.loc
                          (qualified ^ ": opaque call " ^ target
                         ^ "; document the delegated/callback limit"))
                    effects.opaque;
                  if List.mem "ox-cancel-safety" rules then begin
                    let resource_claim =
                      List.exists
                        (fun doc ->
                          List.exists (contains doc)
                            [
                              "no resource left";
                              "no resources left";
                              "leaves no resource";
                              "no resource remains";
                            ]
                          || contains doc "leaves nothing" || contains doc "cancel-safe"
                          || contains doc "safe to re-run")
                        docs
                    in
                    if resource_claim then begin
                      let missing, opaque =
                        cleanup_obligations ~caps evidence
                          (Hashtbl.find evidence.definitions key)
                      in
                      List.iter
                        (fun resource ->
                          report "ox-cancel-safety"
                            ("cleanup of " ^ resource
                           ^ " is not witnessed before cancellation can escape"))
                        missing;
                      List.iter
                        (fun resource ->
                          undecided value.loc
                            (qualified ^ ": cancellation-path cleanup of " ^ resource
                           ^ " depends on opaque calls"))
                        opaque
                    end;
                    if
                      valid claims "cancellation" [ "protected throughout" ]
                      && ((not (Names.is_empty effects.cancellation))
                         || Names.mem cancelled effects.explicit_raises)
                    then
                      report "ox-cancel-safety"
                        "documented protected throughout; cancellation can escape"
                  end)
            (List.rev !selected_values)
        with ex ->
          undecided Location.none
            (Compilation_unit.name_as_string artifact.info.cmt_modname
            ^ ": documentation truth evidence unavailable: " ^ Printexc.to_string ex))
  | _ -> ()
