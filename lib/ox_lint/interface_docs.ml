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
  declaration_only : bool;
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
  let declaration_only = ref false in
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
        let previous, parent, abstract = (!defaults, !modules, !declaration_only) in
        declaration_only := true;
        defaults := merge !defaults (default_fields md.mtd_attributes);
        modules := !modules @ [ md.mtd_name.txt ];
        base.module_type_declaration self md;
        defaults := previous;
        modules := parent;
        declaration_only := abstract);
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
                declaration_only = !declaration_only;
                documentation =
                  texts value.val_attributes
                  @ List.map
                      (fun (label, sentence) -> label ^ ": " ^ sentence ^ ".")
                      (let own = fields (texts value.val_attributes) in
                       List.filter
                         (fun (label, _) -> not (List.mem_assoc label own))
                         (merge !defaults own));
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

(* ^nlintd-truth ^nlintd-raises: retain the callee's handler around each callback
   demand. Canonical transfers, rather than growing filter lists, keep recursive
   callback propagation finite. Each route maps one exception atom to at most one
   atom; these operations distribute over union. *)
type route = { excluded : Names.t; destination : string option; explicit : bool }
type transfer = { direct : route; checked : route; dynamic : route; protected : bool }

let route explicit = { excluded = Names.empty; destination = None; explicit }

let identity =
  { direct = route true; checked = route false; dynamic = route false; protected = false }

let dead_route = { excluded = Names.singleton "*"; destination = None; explicit = false }
let dead route = Names.mem "*" route.excluded

module Transfers = Set.Make (struct
  type t = transfer

  let compare_route a b =
    match Names.compare a.excluded b.excluded with
    | 0 -> compare (a.destination, a.explicit) (b.destination, b.explicit)
    | n -> n

  let compare a b =
    match compare_route a.direct b.direct with
    | 0 -> (
        match compare_route a.checked b.checked with
        | 0 -> (
            match compare_route a.dynamic b.dynamic with
            | 0 -> Bool.compare a.protected b.protected
            | n -> n)
        | n -> n)
    | n -> n
end)

module Demands = Map.Make (String)

type effects = {
  suspension : Names.t;
  cancellation : Names.t;
  check_reachability : Names.t;
  exceptions : Names.t;
  explicit_raises : Names.t;
  opaque : Names.t;
  opaque_raises : Names.t;
  demands : Transfers.t Demands.t;
}

type transformation = Filter of Names.t * bool | Wrap of string

type edge = {
  target : string;
  filters : transformation list;
  bindings : (string * summary) list;
}

and summary = { effects : effects; calls : edge list }

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
  mutable builders : (unit -> unit) list;
}

let empty_effects =
  {
    suspension = Names.empty;
    cancellation = Names.empty;
    check_reachability = Names.empty;
    exceptions = Names.empty;
    explicit_raises = Names.empty;
    opaque = Names.empty;
    opaque_raises = Names.empty;
    demands = Demands.empty;
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
    opaque_raises = Names.union a.opaque_raises b.opaque_raises;
    demands = Demands.union (fun _ a b -> Some (Transfers.union a b)) a.demands b.demands;
  }

let join a b = { effects = union a.effects b.effects; calls = a.calls @ b.calls }
let joins xs = List.fold_left join empty_summary xs

let unknown name =
  { empty_summary with effects = { empty_effects with opaque = Names.singleton name } }

let unknown_call name =
  let summary = unknown name in
  if String.contains name ':' then
    {
      summary with
      effects =
        {
          summary.effects with
          demands = Demands.singleton name (Transfers.singleton identity);
        };
    }
  else summary

(* ^nlintd-truth: an unresolved exception identity cannot itself suspend or check cancellation. *)
let unknown_raise name =
  {
    empty_summary with
    effects = { empty_effects with opaque_raises = Names.singleton name };
  }

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

let filter_route handled protected dynamic route =
  if dead route then dead_route
  else
    let handled =
      if protected && (not route.explicit) && not dynamic then Names.add cancelled handled
      else handled
    in
    match route.destination with
    | Some name ->
        if Names.mem "*" handled || Names.mem name handled then dead_route else route
    | None ->
        if Names.mem "*" handled then dead_route
        else if dynamic then route
        else { route with excluded = Names.union route.excluded handled }

let transfer_step transformation transfer =
  match transformation with
  | Filter (handled, protected) ->
      {
        direct = filter_route handled protected false transfer.direct;
        checked = filter_route handled protected false transfer.checked;
        dynamic =
          filter_route handled protected
            (transfer.dynamic.destination = None)
            transfer.dynamic;
        protected = transfer.protected || protected;
      }
  | Wrap name ->
      let wrap route =
        if dead route then dead_route
        else { route with destination = Some name; explicit = true }
      in
      {
        transfer with
        direct = wrap transfer.direct;
        checked = wrap transfer.checked;
        dynamic = wrap transfer.dynamic;
      }

let compose_route dynamic inner outer =
  if dead inner || dead outer then dead_route
  else
    match inner.destination with
    | Some name when Names.mem name outer.excluded -> dead_route
    | Some name ->
        {
          inner with
          destination = Some (Option.value ~default:name outer.destination);
          explicit = outer.explicit;
        }
    | None ->
        {
          excluded =
            (if dynamic then inner.excluded else Names.union inner.excluded outer.excluded);
          destination = outer.destination;
          explicit = outer.explicit;
        }

let compose inner outer =
  let route dynamic r =
    let next =
      if dynamic && r.destination = None then outer.dynamic
      else if r.explicit then outer.direct
      else outer.checked
    in
    compose_route dynamic r next
  in
  {
    direct = route false inner.direct;
    checked = route false inner.checked;
    dynamic = route true inner.dynamic;
    protected = inner.protected || outer.protected;
  }

let map_demands f demands =
  Demands.map
    (fun transfers ->
      Transfers.fold (fun t out -> Transfers.add (f t) out) transfers Transfers.empty)
    demands

let apply_transfer transfer effects =
  let apply dynamic route names =
    let names = if dead route then Names.empty else Names.diff names route.excluded in
    match route.destination with
    | Some name when not (Names.is_empty names) -> (Names.singleton name, Names.empty)
    | _ when dynamic -> (Names.empty, names)
    | _ -> (names, Names.empty)
  in
  let direct, _ = apply false transfer.direct effects.explicit_raises in
  let checked, _ =
    apply false transfer.checked (Names.diff effects.exceptions effects.explicit_raises)
  in
  let dynamic, opaque_raises = apply true transfer.dynamic effects.opaque_raises in
  let explicit route names = if route.explicit then names else Names.empty in
  {
    effects with
    exceptions = Names.union direct (Names.union checked dynamic);
    explicit_raises =
      Names.union
        (explicit transfer.direct direct)
        (Names.union
           (explicit transfer.checked checked)
           (explicit transfer.dynamic dynamic));
    opaque_raises;
    cancellation = (if transfer.protected then Names.empty else effects.cancellation);
    demands = map_demands (fun inner -> compose inner transfer) effects.demands;
  }

let transform transformation effects =
  apply_transfer (transfer_step transformation identity) effects

let filter_effects handled protected effects =
  transform (Filter (handled, protected)) effects

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
    ("Eio.Fiber.check", false, true, []);
    (* Source-verified allocation leaves, not a blanket Eio exemption. ^nlintd-truth *)
    ("Eio.Promise.create", false, false, []);
    ("Eio.Promise.create_resolved", false, false, []);
    ("Eio.Condition.create", false, false, []);
    ("Eio.Mutex.create", false, false, []);
    ("Eio.Semaphore.make", false, false, [ "Invalid_argument" ]);
    ("Eio.Promise.await", true, true, []);
    ("Eio.Promise.await_exn", true, true, []);
    ("Eio.Stream.add", true, true, []);
    ("Eio.Stream.take", true, true, []);
    ("Eio.Condition.await", true, true, [ "Eio.Mutex.Poisoned" ]);
    ("Eio.Condition.await_no_mutex", true, true, []);
    ("Eio.Mutex.lock", true, true, []);
    ("Eio.Semaphore.acquire", true, true, []);
    ("Eio.Time.sleep", true, true, []);
    ("Eio.Time.Mono.sleep", true, true, []);
    ("Eio.Time.Mono.sleep_until", true, true, []);
    ("Eio.Switch.check", false, true, [ "Invalid_argument" ]);
    ("Eio.Cancel.check", false, true, [ "Invalid_argument" ]);
    ("Eio.Switch.on_release", false, false, [ "Invalid_argument" ]);
    ("Eio.Switch.on_release_cancellable", false, false, [ "Invalid_argument" ]);
    (* ^nlintd-truth: installed 5.4.0+ox stdlib.mli:729, option.mli:38,
       string.mli:251 and result.mli:64 specify these synchronous total leaves. *)
    ("Stdlib.int_of_string_opt", false, false, []);
    (* ^nlintd-truth: installed stdlib.ml:279 fixes the decimal format;
       filename.ml:303 guards the only indexed access before concatenation. *)
    ("Stdlib.string_of_int", false, false, []);
    ("Stdlib.Filename.concat", false, false, []);
    ("Stdlib.Option.value", false, false, []);
    ("Stdlib.String.trim", false, false, []);
    ("Stdlib.Result.bind", false, false, []);
    (* ^nlintd-truth: installed result.ml:62 is exactly an alias of bind. *)
    ("Stdlib.Result.Syntax.let*", false, false, []);
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
    "Thread.create";
    "Domain.spawn";
    (* ^nlintd-truth: source-verified ownership/storage boundaries. *)
    "Eio.Fiber.fork";
    "Eio.Fiber.fork_daemon";
    "Eio.Fiber.fork_promise";
    "Eio.Domain_manager.run";
    "Eio_main.run";
    "Eio.Switch.run";
    "Eio.Time.with_timeout";
    "Eio.Time.with_timeout_exn";
    "Eio.Time.Timeout.run";
    "Eio.Time.Timeout.run_exn";
    "Eio.Mutex.use_ro";
    "Eio.Mutex.use_rw";
    "Eio.Pool.use";
    "Ox_json.Of_json.list";
    "Ox_json.Of_json.option";
    "Ox_json.Of_json.field";
    "Ox_sql_dsl.transaction";
    "Stdlib.Hashtbl.replace";
    "Stdlib.Hashtbl.add";
    "Stdlib.List.iter";
    "Stdlib.List.map";
    "Stdlib.List.filter_map";
    "Stdlib.List.fold_left";
    "Stdlib.List.fold_right";
    "Stdlib.Array.iter";
    "Stdlib.Array.map";
    "Stdlib.Option.iter";
    "Stdlib.Option.map";
    "Stdlib.List.mapi";
    "Stdlib.List.filter";
    "Stdlib.List.concat_map";
    "Stdlib.List.find";
    "Stdlib.List.find_opt";
    "Stdlib.List.find_map";
    "Stdlib.List.exists";
    "Stdlib.List.for_all";
    "Stdlib.List.sort";
    "Stdlib.List.sort_uniq";
    "Stdlib.Array.find_opt";
    "Stdlib.String.iter";
    "Stdlib.String.map";
    "Stdlib.String.for_all";
    "Stdlib.Hashtbl.iter";
    "Stdlib.Option.bind";
    "Stdlib.Option.fold";
    "Stdlib.Result.map";
    "Stdlib.Result.map_error";
    "Stdlib.|>";
    "Stdlib.@@";
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
        if
          List.mem name [ "Fun.protect"; "Printexc.raise_with_backtrace"; "Domain.spawn" ]
        then "Stdlib." ^ name
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

(* ^nlintd-truth: deliberately known non-suspending, non-resource primitives.
   This is not a blanket Stdlib exemption: absent primitives remain opaque. *)
(* ^nlintd-truth: stdlib.mli:128-162 excludes arbitrary polymorphic comparison.
   Scalar instantiations cannot reach functional values or cyclic structures. *)
let scalar_type ty =
  match Types.get_desc ty with
  | Tconstr (path, _, _) ->
      List.exists (Path.same path)
        [
          Predef.path_int;
          Predef.path_float;
          Predef.path_char;
          Predef.path_string;
          Predef.path_bool;
          Predef.path_unit;
        ]
  | _ -> false

let scalar_comparison ty =
  match Types.get_desc ty with
  | Tarrow (_, argument, _, _) -> scalar_type argument
  | _ -> false

let primitive_is_pure ?argument e description =
  match description.Types.val_kind with
  | Val_prim primitive ->
      List.mem primitive.Primitive.prim_name
        [
          "%identity";
          "%ignore";
          "%addint";
          "%subint";
          "%mulint";
          "%andint";
          "%orint";
          "%xorint";
          "%lslint";
          "%lsrint";
          "%asrint";
          "%negint";
          "%succint";
          "%predint";
          "%negfloat";
          "%addfloat";
          "%subfloat";
          "%mulfloat";
          "%divfloat";
          "%absfloat";
          "%floatofint";
          "%intoffloat";
          "%atomic_load";
          "%atomic_set";
          "%atomic_exchange";
          "%atomic_cas";
          "%atomic_fetch_add";
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
      || List.mem primitive.Primitive.prim_name
           [
             "%equal";
             "%notequal";
             "%lessthan";
             "%greaterthan";
             "%lessequal";
             "%greaterequal";
             "%compare";
           ]
         && Option.fold ~none:(scalar_comparison e.exp_type) ~some:scalar_type argument
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
  let pure_callee args e =
    let argument =
      match args with (_, first) :: _ -> Some first.exp_type | [] -> None
    in
    match e.exp_desc with
    | Texp_ident { desc; _ } -> primitive_is_pure ?argument e desc
    | _ -> false
  in
  (* ^nlintd-truth: invoking an exported alias has the same leaf semantics as
     applying it; reading a non-function value is not a call. *)
  let leaf name suspends checks exceptions =
    let summary =
      {
        empty_summary with
        effects =
          {
            empty_effects with
            suspension = (if suspends then Names.singleton name else Names.empty);
            cancellation = (if checks then Names.singleton name else Names.empty);
            check_reachability = (if checks then Names.singleton name else Names.empty);
            exceptions = Names.of_list (exceptions @ if checks then [ cancelled ] else []);
          };
      }
    in
    if name = "Eio.Promise.await_exn" then
      join summary (unknown_raise (name ^ " stored exception"))
    else summary
  in
  let local_definition e =
    match e.exp_desc with
    | Texp_ident { path; _ } ->
        let name = key e path in
        let name = Option.value (Hashtbl.find_opt evidence.exports name) ~default:name in
        Option.map
          (fun definition -> (name, definition))
          (Hashtbl.find_opt evidence.definitions name)
    | _ -> None
  in
  let rec parameters e =
    match e.exp_desc with
    | Texp_function { params; body = Tfunction_body body; _ } -> params @ parameters body
    | Texp_function { params; _ } -> params
    | Texp_let (_, _, body) | Texp_sequence (_, _, body) -> parameters body
    | _ -> []
  in
  let closures = Expressions.create 16 and next_closure = ref 0 in
  (* ^nlintd-truth: an application is a graph node plus its actual substitution.
     Publish pending nodes before descending: a recursive prefix may demand the
     very application whose summary is still being constructed. *)
  let nodes = Expressions.create 32 and next_node = ref 0 in
  let node e =
    match Expressions.find_opt nodes e with
    | Some id -> id
    | None ->
        incr next_node;
        Expressions.add nodes e !next_node;
        !next_node
  in
  let state partial callee actuals =
    let callee =
      match local_definition callee with
      | Some (_, definition) -> definition.body
      | None -> callee
    in
    (node callee, partial, List.map (fun (label, actual) -> (label, node actual)) actuals)
  in
  let applications = Hashtbl.create 32 and next_application = ref 0 in
  let rec invokes e =
    match e.exp_desc with
    | Texp_function { body = Tfunction_body body; _ } ->
        if function_typed body then invokes body else expression body
    | Texp_function { body = Tfunction_cases cases; _ } ->
        joins
          (List.map
             (fun c ->
               join
                 (joins (List.map expression (Option.to_list c.c_guard)))
                 (if function_typed c.c_rhs then invokes c.c_rhs else expression c.c_rhs))
             cases.fc_cases)
    | Texp_ident { path; desc; _ } -> (
        if (not (function_typed e)) || primitive_is_pure e desc then empty_summary
        else
          match List.assoc_opt (origin e) leaves with
          | Some (name, suspends, checks, exceptions) ->
              leaf name suspends checks exceptions
          | None ->
              {
                empty_summary with
                calls = [ { target = key e path; filters = []; bindings = [] } ];
              })
    | Texp_apply (callee, args, _, _, _) when function_typed e ->
        join (expression e) (application [] false callee (arguments args))
    | Texp_let (_, bindings, body) when function_typed e ->
        join (joins (List.map (fun vb -> expression vb.vb_expr) bindings)) (invokes body)
    | Texp_sequence (first, _, last) when function_typed e ->
        join (expression first) (invokes last)
    | Texp_ifthenelse (condition, yes, no) when function_typed e ->
        joins (expression condition :: invokes yes :: List.map invokes (Option.to_list no))
    | _ -> expression e
  and bindings definition actuals =
    let rec select label prefix = function
      | [] -> (None, List.rev prefix)
      | (actual_label, actual) :: rest when label = actual_label ->
          (Some actual, List.rev_append prefix rest)
      | item :: rest -> select label (item :: prefix) rest
    in
    let rec bind actuals = function
      | [] -> []
      | parameter :: rest ->
          let actual, actuals = select parameter.fp_arg_label [] actuals in
          let pattern, actual =
            match parameter.fp_kind with
            | Tparam_pat pattern -> (pattern, actual)
            | Tparam_optional_default (pattern, default, _) ->
                let actual =
                  match actual with
                  | Some { exp_desc = Texp_construct (_, d, _, [ (_, value) ], _); _ }
                    when d.cstr_name = "Some" ->
                      Some value
                  | Some { exp_desc = Texp_construct (_, d, _, [], _); _ }
                    when d.cstr_name = "None" ->
                      Some default
                  | None -> Some default
                  | actual -> actual
                in
                (pattern, actual)
          in
          let bound =
            match actual with
            | Some actual when function_typed actual ->
                List.map
                  (fun id -> (local_key definition.unit_name id, invokes actual))
                  (Typedtree.pat_bound_idents pattern)
            | _ -> []
          in
          bound @ bind actuals rest
    in
    bind actuals (parameters definition.body)
  and application seen partial callee actuals =
    let ((callee_node, _, _) as current) = state partial callee actuals in
    match Hashtbl.find_opt applications current with
    | Some (_, { contents = Some summary }) -> summary
    | Some (name, _) ->
        if not (Hashtbl.mem evidence.definitions name) then
          Hashtbl.add evidence.definitions name
            { body = callee; unit_name; summary = empty_summary };
        { empty_summary with calls = [ { target = name; filters = []; bindings = [] } ] }
    | None when List.exists (fun (node, _, _) -> node = callee_node) seen ->
        (* A repeated alias with a growing actual list cannot have a finite state
           key. Name that unresolved substitution, rather than cap its depth. *)
        unknown (origin callee ^ " regenerating partial-application substitution")
    | None ->
        incr next_application;
        let name = unit_name ^ ":application-" ^ string_of_int !next_application in
        let pending = ref None in
        Hashtbl.add applications current (name, pending);
        let summary = application_body (current :: seen) partial callee actuals in
        pending := Some summary;
        Option.iter
          (fun definition -> definition.summary <- summary)
          (Hashtbl.find_opt evidence.definitions name);
        summary
  and application_body seen partial callee actuals =
    let edge name definition =
      {
        empty_summary with
        calls =
          [ { target = name; filters = []; bindings = bindings definition actuals } ];
      }
    in
    match local_definition callee with
    | Some (name, definition) -> (
        match definition.body.exp_desc with
        | Texp_ident _ -> application seen partial definition.body actuals
        | Texp_apply (fn, stored, _, _, _) ->
            application seen partial fn (arguments stored @ actuals)
        | Texp_function { params; body; _ } when partial ->
            let supplied = List.map fst actuals in
            let rec remaining supplied = function
              | [] -> Some supplied
              | p :: rest ->
                  let rec remove prefix = function
                    | [] -> None
                    | label :: labels when label = p.fp_arg_label ->
                        Some (List.rev_append prefix labels)
                    | label :: labels -> remove (label :: prefix) labels
                  in
                  Option.bind (remove [] supplied) (fun supplied ->
                      remaining supplied rest)
            in
            let executes_body =
              match (remaining supplied params, body) with
              | None, _ -> false
              | Some _, Tfunction_body _ -> true
              (* The final case-function parameter is not in [params]. A callback
                 such as [map fixed] must not execute [function ...] yet. *)
              | Some supplied, Tfunction_cases _ -> List.mem Nolabel supplied
            in
            if not executes_body then empty_summary
            else
              let prefix = name ^ ":application-prefix" in
              if not (Hashtbl.mem evidence.definitions prefix) then begin
                let pending = { definition with summary = empty_summary } in
                Hashtbl.add evidence.definitions prefix pending;
                let summary =
                  match body with
                  | Tfunction_body body -> expression body
                  | Tfunction_cases cases ->
                      joins
                        (List.concat_map
                           (fun c ->
                             List.map expression (Option.to_list c.c_guard @ [ c.c_rhs ]))
                           cases.fc_cases)
                in
                pending.summary <- summary
              end;
              edge prefix definition
        | _ -> edge name definition)
    | _ -> (
        match callee.exp_desc with
        | Texp_apply (fn, stored, _, _, _) ->
            application seen partial fn (arguments stored @ actuals)
        | Texp_function _ ->
            let name =
              match Expressions.find_opt closures callee with
              | Some name -> name
              | None ->
                  incr next_closure;
                  let name = unit_name ^ ":closure-" ^ string_of_int !next_closure in
                  Expressions.add closures callee name;
                  let pending = { body = callee; unit_name; summary = empty_summary } in
                  Hashtbl.add evidence.definitions name pending;
                  pending.summary <- invokes callee;
                  name
            in
            edge name (Hashtbl.find evidence.definitions name)
        | _ when partial -> unknown (origin callee ^ " partial application")
        | _ when pure_callee actuals callee -> empty_summary
        | _ ->
            let invocation = invokes callee in
            if List.exists (fun (_, actual) -> function_typed actual) actuals then
              join invocation (unknown ("callback invocation by " ^ origin callee))
            else invocation)
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
                  | None -> unknown_raise "dynamic exception re-raise")
              | [] -> unknown "raise without exception evidence")
          | Some "Stdlib.invalid_arg" -> thrown "Invalid_argument"
          | Some "Stdlib.failwith" -> thrown "Failure"
          (* ^nlintd-truth: native thread/domain creation does not invoke its
             callback in the caller. Definitions retain their own summaries;
             creation can fail synchronously, but cannot suspend the Eio fiber.
             Domain_manager.run is deliberately not a spawning exemption. *)
          | Some (("Thread.create" | "Domain.spawn") as name) -> unknown_raise name
          (* ^nlintd-truth ^nlintd-raises: fork starts another fiber. Its callback
             fails the owner switch/promise, not this call. Eio's fork functions
             check the switch synchronously (domain/finished: Invalid_argument),
             but perform no caller cancellation check. Waits are separate calls. *)
          | Some
              ( "Eio.Fiber.fork" | "Eio.Fiber.fork_daemon" | "Eio.Fiber.fork_promise"
              | "Eio.Domain_manager.run" | "Eio_main.run" | "Eio.Switch.run"
              | "Eio.Time.with_timeout" | "Eio.Time.with_timeout_exn"
              | "Eio.Time.Timeout.run" | "Eio.Time.Timeout.run_exn" | "Eio.Mutex.use_ro"
              | "Eio.Mutex.use_rw" | "Eio.Pool.use" | "Ox_json.Of_json.list"
              | "Ox_json.Of_json.option" | "Ox_json.Of_json.field"
              | "Ox_sql_dsl.transaction" | "Stdlib.Hashtbl.replace" | "Stdlib.Hashtbl.add"
              | "Stdlib.List.iter" | "Stdlib.List.map" | "Stdlib.List.filter_map"
              | "Stdlib.List.fold_left" | "Stdlib.List.fold_right" | "Stdlib.Array.iter"
              | "Stdlib.Array.map" | "Stdlib.Array.find_opt" | "Stdlib.Option.iter"
              | "Stdlib.Option.map" | "Stdlib.Option.bind" | "Stdlib.Option.fold"
              | "Stdlib.List.mapi" | "Stdlib.List.filter" | "Stdlib.List.concat_map"
              | "Stdlib.List.find" | "Stdlib.List.find_opt" | "Stdlib.List.find_map"
              | "Stdlib.List.exists" | "Stdlib.List.for_all" | "Stdlib.List.sort"
              | "Stdlib.List.sort_uniq" | "Stdlib.String.iter" | "Stdlib.String.map"
              | "Stdlib.String.for_all" | "Stdlib.Hashtbl.iter" | "Stdlib.Result.map"
              | "Stdlib.Result.map_error" | "Stdlib.|>" | "Stdlib.@@" )
            when function_typed e ->
              application [] true callee args
          | Some
              (("Eio.Fiber.fork" | "Eio.Fiber.fork_daemon" | "Eio.Fiber.fork_promise") as
               name) ->
              leaf name false false [ "Invalid_argument" ]
          | Some
              ( "Eio_main.run" | "Eio.Switch.run" | "Eio.Time.with_timeout"
              | "Eio.Time.with_timeout_exn" | "Eio.Time.Timeout.run"
              | "Eio.Time.Timeout.run_exn" | "Eio.Mutex.use_ro" | "Eio.Mutex.use_rw"
              | "Eio.Pool.use" ) as contract ->
              (* Eio source: these callbacks execute before this caller returns.
                 Keep the callee opaque; this is invocation, not a purity claim. *)
              let callback =
                match List.rev args with
                | (_, callback) :: _ -> invokes callback
                | [] -> unknown "missing immediate callback"
              in
              let callback =
                if
                  contract = Some "Eio.Mutex.use_rw"
                  && List.exists
                       (fun (label, value) ->
                         label = Typedtree.Labelled "protect"
                         &&
                         match value.exp_desc with
                         | Texp_construct (_, d, _, [], _) -> d.cstr_name = "true"
                         | _ -> false)
                       args
                then under Names.empty true callback
                else callback
              in
              let body = join (invokes callee) callback in
              if contract = Some "Eio.Switch.run" then
                joins
                  [
                    body;
                    leaf "Eio.Switch.run" false true [];
                    unknown_raise "Eio.Switch.run owned-fiber failure";
                    unknown "callback invocation by Eio.Switch.run owned-fiber failure";
                  ]
              else body
          | Some ("Ox_json.Of_json.list" | "Ox_json.Of_json.option") ->
              (* lib/json/ox_json.ml:127-158: only the decoder is invoked. *)
              join (invokes callee)
                (match args with
                | (_, callback) :: _ -> invokes callback
                | [] -> empty_summary)
          | Some "Ox_json.Of_json.field" ->
              join (invokes callee)
                (match args with
                | _ :: (_, callback) :: _ -> invokes callback
                | _ -> empty_summary)
          | Some "Ox_sql_dsl.transaction" ->
              (* lib/sql_dsl/ox_sql_dsl.ml:66-104: every callback's exception is
                 returned as Raised, not synchronously propagated. *)
              let callbacks =
                List.filter_map
                  (fun (label, value) ->
                    if
                      List.mem label
                        [
                          Typedtree.Labelled "begin_";
                          Typedtree.Labelled "commit";
                          Typedtree.Labelled "rollback";
                        ]
                    then Some (invokes value)
                    else None)
                  args
              in
              let callbacks =
                match List.rev args with
                | (_, callback) :: _ -> invokes callback :: callbacks
                | [] -> callbacks
              in
              join (invokes callee) (under (Names.singleton "*") false (joins callbacks))
          | Some "Eio.Domain_manager.run" ->
              (* A joined domain re-delivers failures to its waiting caller. *)
              join
                (leaf "Eio.Domain_manager.run" true true [ "Eio.Cancel.Cancelled" ])
                (match List.rev args with
                | (_, callback) :: _ -> invokes callback
                | [] -> unknown "Eio.Domain_manager.run callback")
          | Some ("Stdlib.Hashtbl.replace" | "Stdlib.Hashtbl.add") ->
              (* Values, including closures, are stored, not invoked. Hash/equality
                 remain external evidence, not a blanket purity assumption. *)
              invokes callee
          | Some ("Stdlib.Option.bind" | "Stdlib.|>") ->
              join (invokes callee)
                (match List.filter (fun (label, _) -> label = Typedtree.Nolabel) args with
                | _ :: (_, callback) :: _ -> invokes callback
                | _ -> unknown ("missing immediate callback for " ^ origin callee))
          | Some "Stdlib.Option.fold" ->
              join (invokes callee)
                (joins
                   (List.filter_map
                      (fun (label, arg) ->
                        if label = Typedtree.Labelled "some" then Some (invokes arg)
                        else None)
                      args))
          | Some
              ( "Stdlib.List.iter" | "Stdlib.List.map" | "Stdlib.List.filter_map"
              | "Stdlib.List.fold_left" | "Stdlib.List.fold_right" | "Stdlib.Array.iter"
              | "Stdlib.Array.map" | "Stdlib.Option.iter" | "Stdlib.Option.map"
              | "Stdlib.List.mapi" | "Stdlib.List.filter" | "Stdlib.List.concat_map"
              | "Stdlib.List.find" | "Stdlib.List.find_opt" | "Stdlib.List.find_map"
              | "Stdlib.List.exists" | "Stdlib.List.for_all" | "Stdlib.List.sort"
              | "Stdlib.List.sort_uniq" | "Stdlib.Array.find_opt" | "Stdlib.String.iter"
              | "Stdlib.String.map" | "Stdlib.String.for_all" | "Stdlib.Hashtbl.iter"
              | "Stdlib.Result.map" | "Stdlib.Result.map_error" | "Stdlib.@@" ) ->
              join (invokes callee)
                (match args with
                | (_, callback) :: _ -> invokes callback
                | [] -> unknown ("missing immediate callback for " ^ origin callee))
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
              (* Eio switch.ml:164-177: a live switch stores the hook, but a
                 finished switch invokes it protected now, then raises. *)
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
                  join
                    (leaf name suspends checks exceptions)
                    (if
                       function_typed e
                       || not
                            (List.mem name
                               [ "Stdlib.Result.bind"; "Stdlib.Result.Syntax.let*" ])
                     then empty_summary
                     else
                       joins
                         (List.filter_map
                            (fun (_, arg) ->
                              if function_typed arg then Some (invokes arg) else None)
                            args))
              | None when pure_callee args callee -> empty_summary
              | None -> application [] (function_typed e) callee args)
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
    | Texp_letop { let_; ands; body; _ } ->
        (* ^nlintd-truth: a binding operator is a path-resolved ordinary call. *)
        let callback =
          joins (List.map expression (Option.to_list body.c_guard @ [ body.c_rhs ]))
        in
        let rec operator seen op target callback =
          match Hashtbl.find_opt evidence.definitions target with
          | Some definition when not (List.mem target seen) -> (
              match definition.body.exp_desc with
              | Texp_ident { path; _ } ->
                  operator (target :: seen) op (key definition.body path) callback
              | _ ->
                  let callback_parameters =
                    match callback with
                    | None -> []
                    | Some summary -> (
                        match List.rev (parameters definition.body) with
                        | p :: _ -> (
                            let pattern =
                              match p.fp_kind with
                              | Tparam_pat p | Tparam_optional_default (p, _, _) -> p
                            in
                            match Types.get_desc pattern.pat_type with
                            | Tarrow _ ->
                                List.map
                                  (fun id -> (local_key definition.unit_name id, summary))
                                  (Typedtree.pat_bound_idents pattern)
                            | _ -> [])
                        | [] -> [])
                  in
                  let invocation =
                    {
                      empty_summary with
                      calls =
                        [
                          {
                            target;
                            filters = [];
                            bindings =
                              bindings definition [ (Nolabel, op.bop_exp) ]
                              @ callback_parameters;
                          };
                        ];
                    }
                  in
                  if callback_parameters = [] then
                    join invocation (joins (Option.to_list callback))
                  else invocation)
          | _ ->
              let invocation =
                match List.assoc_opt target leaves with
                | Some (name, suspends, checks, exceptions) ->
                    leaf name suspends checks exceptions
                | None ->
                    {
                      empty_summary with
                      calls = [ { target; filters = []; bindings = [] } ];
                    }
              in
              join invocation (joins (Option.to_list callback))
        in
        joins
          (expression let_.bop_exp
          :: operator [] let_ (key e let_.bop_op_path) (Some callback)
          :: List.concat_map
               (fun op ->
                 [ expression op.bop_exp; operator [] op (key e op.bop_op_path) None ])
               ands)
    | _ -> children empty_summary e
  and children initial e =
    let result = ref initial in
    let walk =
      { base with expr = (fun _ child -> result := join !result (expression child)) }
    in
    base.expr walk e;
    !result
  in
  (* ^nlintd-truth: publish every unit's declarations before constructing calls;
     otherwise file order turns available cross-unit callbacks into opaque ones. *)
  evidence.builders <-
    (fun () ->
      Artifact.setup ~caps artifact;
      Hashtbl.to_seq_values evidence.definitions
      |> List.of_seq
      |> List.iter (fun definition ->
          if definition.unit_name = unit_name then
            definition.summary <- invokes definition.body))
    :: evidence.builders

(* ^nlintd-truth: callback substitutions are summaries on finite graph edges, not
   recursive AST expansion. Only callback demands actually reached by a callee are
   substituted; merely passing a closure does not execute it. *)
let rec summary_effects evidence summary =
  List.fold_left
    (fun effects edge -> union effects (edge_effects evidence edge))
    summary.effects summary.calls

and edge_effects evidence edge =
  let key =
    Option.value (Hashtbl.find_opt evidence.exports edge.target) ~default:edge.target
  in
  let callee =
    Option.value
      (Hashtbl.find_opt evidence.resolved key)
      ~default:(unknown_call edge.target).effects
  in
  let substituted =
    List.fold_left
      (fun effects (parameter, actual) ->
        match Demands.find_opt parameter callee.demands with
        | None -> effects
        | Some transfers ->
            let actual = summary_effects evidence actual in
            let bound =
              Transfers.fold
                (fun transfer out -> union out (apply_transfer transfer actual))
                transfers empty_effects
            in
            union
              {
                effects with
                opaque = Names.remove parameter effects.opaque;
                demands = Demands.remove parameter effects.demands;
              }
              bound)
      callee edge.bindings
  in
  apply_filters edge.filters substituted

let resolve evidence =
  List.iter (fun build -> build ()) (List.rev evidence.builders);
  evidence.builders <- [];
  let reverse = Hashtbl.create 128 in
  let target key = Option.value (Hashtbl.find_opt evidence.exports key) ~default:key in
  let rec depend name summary =
    List.iter
      (fun edge ->
        let key = target edge.target in
        if Hashtbl.mem evidence.definitions key then
          Hashtbl.replace reverse key
            (name :: Option.value (Hashtbl.find_opt reverse key) ~default:[]);
        List.iter (fun (_, actual) -> depend name actual) edge.bindings)
      summary.calls
  in
  Hashtbl.iter
    (fun name definition ->
      depend name definition.summary;
      Hashtbl.replace evidence.resolved name definition.summary.effects)
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
    let after = union before (summary_effects evidence definition.summary) in
    if
      not
        (Names.equal after.suspension before.suspension
        && Names.equal after.cancellation before.cancellation
        && Names.equal after.check_reachability before.check_reachability
        && Names.equal after.exceptions before.exceptions
        && Names.equal after.explicit_raises before.explicit_raises
        && Names.equal after.opaque before.opaque
        && Names.equal after.opaque_raises before.opaque_raises
        && Demands.equal Transfers.equal after.demands before.demands)
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
          builders = [];
        }
      in
      Cap_sys.readdir ~caps directory
      |> Array.to_list |> List.sort String.compare
      |> List.filter (fun name -> Filename.check_suffix name ".cmt")
      |> List.iter (fun name ->
          let artifact = Artifact.read ~caps (Filename.concat directory name) in
          (* Use the original source, not merely the annotation's build copy. *)
          let build_source = Artifact.source artifact in
          if Filename.check_suffix build_source ".ml-gen" then begin
            (* ^nlintd-truth: deprecated empty modules and constant aliases in
               generated wrappers execute no calls, just like module aliases. *)
            let constant binding =
              match binding.vb_expr.exp_desc with
              | Texp_constant _ | Texp_ident _ | Texp_construct (_, _, _, [], _) -> true
              | _ -> false
            in
            let rec transparent tree = List.for_all transparent_item tree.str_items
            and transparent_item item =
              match item.str_desc with
              | Tstr_module binding -> (
                  match binding.mb_expr.mod_desc with
                  | Tmod_ident _ -> true
                  | Tmod_structure tree -> transparent tree
                  | _ -> false)
              | Tstr_value (_, bindings) -> List.for_all constant bindings
              | Tstr_attribute _ -> true
              | _ -> false
            in
            let aliases_only =
              match artifact.info.cmt_annots with
              | Implementation tree -> transparent tree
              | _ -> false
            in
            if not aliases_only then
              failwith (artifact.path ^ ": generated wrapper is not alias-only")
            (* Alias/constant wrappers contain no executable calls. Canonical compiler
               paths resolve their exports to the actual compilation unit. *)
          end
          else begin
            (* ^nlintd-truth ^nlintcov-q6n2: generated siblings have no source-tree
               counterpart; Artifact verifies their declared producer instead. *)
            let source = Artifact.authored_source ~caps artifact in
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

(* ^nlintd-truth: disclosure is not proof of an author's readiness invariant.
   Only readiness-dependent leaves admit a named qualification; yield still suspends. *)
let readiness_qualified claims label target =
  List.mem target
    [
      "Eio.Stream.add";
      "Eio.Stream.take";
      "Eio.Promise.await";
      "Eio.Promise.await_exn";
      "Eio.Mutex.lock";
      "Eio.Semaphore.acquire";
    ]
  &&
  match List.assoc_opt label claims with
  | None -> false
  | Some text ->
      contains text (String.lowercase_ascii target)
      && List.exists (contains text)
           [ "because"; "when"; "if"; "slot"; "capacity"; "ready" ]

let exception_mentioned docs name =
  let name = String.lowercase_ascii name in
  let short = List.hd (List.rev (String.split_on_char '.' name)) in
  List.exists (fun text -> contains text name || contains text short) docs

let opaque_qualified docs target =
  let prefix = "callback invocation by " in
  let callback = String.starts_with ~prefix target in
  let target =
    if callback then
      String.sub target (String.length prefix)
        (String.length target - String.length prefix)
    else target
  in
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
        (callback && (contains text "callback" || contains text "caller code"))
        || contains target "callback argument to"
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

(* ^nlintd-raises: the author owns a specifically named delegated raise claim;
   this bounds that val's assertion, never supplies evidence to callers. *)
let delegated_raise docs tag target =
  let marker = "@raise " ^ tag in
  List.exists
    (fun text ->
      match index text marker 0 with
      | None -> false
      | Some at ->
          let start = at + String.length marker in
          let stop =
            Option.value (index text "@raise " start) ~default:(String.length text)
          in
          let clause = String.sub text start (stop - start) in
          (contains clause "from" || contains clause "propagat"
         || contains clause "delegat" || contains clause "depends on"
         || contains clause "failure of" || contains clause " if "
         || contains clause " when ")
          && opaque_qualified [ "delegated " ^ clause ] target)
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
    | Some summary -> summary_effects evidence summary
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
    if (not (Names.is_empty effects.opaque)) || not (Names.is_empty effects.opaque_raises)
    then `Unknown
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
        (* ^nlintd-truth: opaque evidence only matters when there is a claim to check.
           Shape rules independently report missing sentences. *)
        let docs = value.documentation in
        let claims = fields docs in
        let asserted =
          List.exists
            (fun label -> List.mem_assoc label claims)
            [ "suspension"; "cancellation"; "cancellation safety" ]
          || raises_tags docs <> []
          || List.exists
               (fun doc ->
                 List.exists (contains doc)
                   [
                     "no resource left";
                     "no resources left";
                     "leaves no resource";
                     "no resource remains";
                     "leaves nothing";
                     "cancel-safe";
                   ])
               docs
        in
        (* ^nlintd-truth: module-type declarations have no executable binding. *)
        if value.families <> [] && asserted && not value.declaration_only then
          selected_values := value :: !selected_values
      in
      let walk = iterator ~caps inspect in
      walk.signature walk tree;
      if !selected_values <> [] then
        try
          let implementation_source = Filename.chop_suffix source ".mli" ^ ".ml" in
          let implementation = Artifact.find ~caps implementation_source in
          Artifact.check ~caps
            ~source:(Artifact.authored_source ~caps implementation)
            implementation;
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
                  let undisclosed_suspension =
                    if no_added then effects.suspension
                    else
                      Names.filter
                        (fun target ->
                          not (readiness_qualified claims "suspension" target))
                        effects.suspension
                  in
                  if
                    (no_suspend || no_added)
                    && not (Names.is_empty undisclosed_suspension)
                  then
                    report "ox-val-behaviour"
                      ("documented never suspends; reaches "
                      ^ String.concat ", " (Names.elements undisclosed_suspension));
                  let checks =
                    if no_added then effects.check_reachability
                    else
                      Names.filter
                        (fun target ->
                          not (readiness_qualified claims "cancellation" target))
                        effects.cancellation
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
                        (not
                           (Names.exists
                              (fun name ->
                                String.lowercase_ascii name = tag
                                || String.lowercase_ascii
                                     (List.hd (List.rev (String.split_on_char '.' name)))
                                   = tag)
                              effects.exceptions))
                        && not
                             (Names.exists (delegated_raise docs tag)
                                (Names.union effects.opaque effects.opaque_raises))
                      then
                        if
                          Names.is_empty effects.opaque
                          && Names.is_empty effects.opaque_raises
                        then
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
                  if
                    List.mem "ox-val-behaviour" rules
                    && (no_suspend || no_check
                       || raises_tags docs <> []
                       || Names.exists
                            (fun target -> contains target "callback invocation by")
                            effects.opaque)
                  then
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
                        if
                          (not bounded)
                          && (no_suspend || no_check
                             || raises_tags docs <> []
                             || contains target "callback invocation by")
                        then
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
