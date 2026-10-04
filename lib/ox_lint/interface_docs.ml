(* ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0: typed selection, lexical defaults and shape only. *)
open Ocaml_common
open Typedtree

type value = {
  name : string;
  loc : Location.t;
  families : string list;
  behaviour : bool;
  cancel_safety : bool;
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

let origins () =
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

let selected origins en ty =
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

let iterator inspect =
  let origins = origins () in
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
            let en =
              Envaux.env_of_only_summary ~allow_missing_modules:false item.sig_env
            in
            let families = selected origins en value.val_desc.ctyp_type in
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
              }
        | _ -> ());
        base.signature_item self item);
  }

let behaviour emit =
  iterator (fun value ->
      if value.families <> [] && not value.behaviour then emit value.loc)

let cancel_safety emit =
  iterator (fun value ->
      if value.families <> [] && not value.cancel_safety then emit value.loc)
