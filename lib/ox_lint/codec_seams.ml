(* ^safe-1kqm ^safe-gm8y ^safe-l2jj: bounded published representations, not JSON names. *)
open Ocaml_common
open Types

type owner = { unit_ : string; source : string; digest : string }

type domain = {
  owner : owner;
  module_ : string;
  roots : string list;
  producers : string list;
  whole : bool;
}

let owner unit_ source digest = { unit_; source; digest }

let domains =
  [
    {
      owner = owner "Ox_http__Url" "lib/http/url" "66f0696e5637ee88ff79add9b8ad4312";
      module_ = "Ox_http.Url";
      roots = [ "t" ];
      producers = [ "parse"; "of_string"; "with_query"; "with_query_param" ];
      whole = true;
    };
    {
      owner = owner "Ox_http__Header" "lib/http/header" "14acccf5b811f27cb024e4cf416447d1";
      module_ = "Ox_http.Header";
      roots = [ "name"; "value" ];
      producers = [ "name"; "value"; "pair" ];
      whole = false;
    };
    {
      owner = owner "Ox_otel__Meter" "lib/otel/meter" "21586d5d4cb9c86801d944d490daf216";
      module_ = "Ox_otel.Meter";
      roots = [ "histogram_config" ];
      producers = [ "histogram_config" ];
      whole = false;
    };
    {
      owner =
        owner "Ox_observability__Logger" "lib/observability/logger"
          "6dc5050bc8bca708a07490dce42177f8";
      module_ = "Ox_observability.Logger";
      roots = [ "limit" ];
      producers = [ "limit" ];
      whole = false;
    };
    {
      owner =
        owner "Ox_observability__Redact" "lib/observability/redact"
          "d8f669757de3284bebec48d68de0f5aa";
      module_ = "Ox_observability.Redact";
      roots = [ "t" ];
      producers = [ "make"; "t_of_yojson" ];
      whole = true;
    };
  ]

(* These are serialization/protocol ownership contracts, not validation contracts.
   No module-wide or type-use permission is inferred from this finite table. *)
let codecs =
  [
    ( (List.nth domains 4).owner,
      "Ox_observability.Redact",
      [ "to_json"; "yojson_of_t"; "t_of_yojson" ] );
    ( owner "Ox_ai_chat__Types" "lib/ai_chat/types" "bc1af010802a46984afc295d9577aaef",
      "Ox_ai_chat.Types",
      [ "yojson_of_request"; "request_of_yojson"; "response_of_yojson" ] );
    ( owner "Ox_ai_systemone__Types" "lib/ai_systemone/types"
        "87fd540367db589a6b4781aa086bb176",
      "Ox_ai_systemone.Types",
      [ "yojson_of_usage"; "usage_of_yojson" ] );
    ( owner "Ox_ai_systemone__Codecs" "lib/ai_systemone/codecs"
        "9cfde6d77b05cffb6528b56907097a9c",
      "Ox_ai_systemone.Codecs",
      [
        "t_of_map";
        "map_of_pairs";
        "t_of_choice_answer";
        "t_of_score_answer";
        "t_of_choice_question";
        "t_of_score_question";
        "choice";
        "score";
        "yojson_of_answer";
        "yojson_of_question";
        "yojson_of_response";
        "yojson_of_request";
        "t_of_answer";
        "t_of_question";
        "t_of_response";
        "t_of_request";
        "response_of_yojson";
      ] );
    ( owner "Ox_ai_systemone__Client" "lib/ai_systemone/client"
        "40d8c230f60ee0d007bbd5410e6154e8",
      "Ox_ai_systemone.Client",
      [ "evaluate" ] );
    ( owner "Ox_ai_realtime__Session" "lib/ai_realtime/session"
        "6821be41d5abe275cf965431c95a41ff",
      "Ox_ai_realtime.Session",
      [ "send"; "decode"; "receive" ] );
    ( owner "Ox_ai_openrouter__Common" "lib/ai_openrouter/common"
        "2045b60f3c3fc2cec1134bdf8fd912a9",
      "Ox_ai_openrouter.Common",
      [ "invalid"; "decode"; "post" ] );
    ( owner "Ox_ai_openrouter__Audio" "lib/ai_openrouter/audio"
        "5b957dd5e4dd6b76790015a843dcb501",
      "Ox_ai_openrouter.Audio",
      [ "decode" ] );
    ( owner "Ox_ai_openrouter__Embeddings" "lib/ai_openrouter/embeddings"
        "897717913edd49a6d6d6aa78ae1f9cda",
      "Ox_ai_openrouter.Embeddings",
      [ "encode"; "decode" ] );
    ( owner "Ox_ai_openrouter__Responses" "lib/ai_openrouter/responses"
        "60ae5aa54333fa090227b780a63bea26",
      "Ox_ai_openrouter.Responses",
      [ "encode"; "encode_text"; "decode" ] );
    ( owner "Ox_app__Config" "lib/app/config" "19b0d344be2a9b9fcf72fed550d72ec0",
      "Ox_app.Config",
      [ "load_decoding" ] );
    ( owner "Ox_app" "lib/app/ox_app" "cc4b012a3834a687a7429a522ca90f0a",
      "Ox_app",
      [ "run_for_test_with_args"; "run_for_test"; "run_with_args"; "run" ] );
    ( owner "Ox_ai__Transport" "lib/ai/transport" "deab4250b6ece0a29e0c190abed15b21",
      "Ox_ai.Transport",
      [ "bytes_of_json" ] );
    ( owner "Ox_http__Service" "lib/http/service" "ffc5a8434f9959286f2d32dd43b5bbef",
      "Ox_http.Service.Json",
      [ "response" ] );
    ((List.nth domains 3).owner, "Ox_observability.Logger", [ "value_to_json"; "to_json" ]);
  ]

let fields =
  [
    ("Ox_ai_systemone.Types.choice_question", [ "instructions"; "criteria" ]);
    ("Ox_ai_systemone.Types.score_question", [ "instructions" ]);
    ("Ox_ai_systemone.Codecs.request", [ "state" ]);
    ("Ox_ai_realtime.Session.event", [ "raw" ]);
    ("Ox_ai_openrouter.Responses.schema", [ "schema" ]);
    ("Ox_app.Config.t", [ "of_yojson"; "yojson_of_t" ]);
  ]

let initial () = Lazy.force Env.initial
let lid name = Option.get (Longident.unflatten (String.split_on_char '.' name))
let optional f = try Some (f ()) with Not_found | Env.Error _ -> None

let type_ name =
  optional (fun () ->
      Env.lookup_type ~use:false ~loc:Location.none (lid name) (initial ()))

let value name =
  optional (fun () ->
      let _, d, _ =
        Env.lookup_value ~use:false ~loc:Location.none (lid name) (initial ())
      in
      d)

let source_is source name = name = source || String.ends_with ~suffix:("/" ^ source) name

let public_source source name =
  source_is (source ^ ".mli") name || source_is (source ^ ".pp.mli") name

let declaration_source d source = public_source source d.type_loc.loc_start.pos_fname

(* Reviewed emitted PPX inputs. The remaining providers have byte-identical .pp copies
   or are compiled directly. Changed generated bodies require a fresh audit. *)
let emitted_digest owner =
  match owner.unit_ with
  | "Ox_ai_systemone__Types" -> "3201263675fa7aad70b5f6a6d174c27b"
  | "Ox_ai_openrouter__Responses" -> "0570b5e09b366ab8d23d9143cf9f85e9"
  | "Ox_ai_chat__Types" -> "4da2cd8c5e895d44cce9f22bda94fa89"
  | "Ox_ai_openrouter__Audio" -> "791f0e3012d86670f68e0a3adaec8334"
  | "Ox_ai_openrouter__Embeddings" -> "a446a716eba38b53421b46b8ca2ec06f"
  | _ -> owner.digest

let raw_names =
  [ "Yojson.Safe.t"; "Yojson.Basic.t"; "Yojson.Raw.t"; "Obj.t"; "Stdlib.Obj.t" ]

let scalar_names =
  [
    "int";
    "int32";
    "int64";
    "nativeint";
    "float";
    "char";
    "string";
    "bytes";
    "bool";
    "unit";
  ]

let check ~caps ~emit ~undecided artifact =
  let emitted = Hashtbl.create 16 in
  let report f loc message =
    let key = (loc.Location.loc_start, message) in
    if not (Hashtbl.mem emitted key) then (
      Hashtbl.add emitted key ();
      f loc message)
  in
  let fail = report undecided and finding = report emit in
  let unit_ = Compilation_unit.name_as_string artifact.Artifact.info.cmt_modname in
  let audits = Hashtbl.create 8 in
  let audited owner loc =
    let decision =
      match Hashtbl.find_opt audits owner.unit_ with
      | Some result -> result
      | None ->
          let result =
            try
              let filename = String.uncapitalize_ascii owner.unit_ in
              ignore caps#fs_read;
              (* Only metadata is needed. An installed provider need not carry its
                 build checkout or a rebasable /workspace_root source tree. *)
              let info = Cmt_format.read_cmt (Load_path.find (filename ^ ".cmt")) in
              if Compilation_unit.name_as_string info.cmt_modname <> owner.unit_ then
                Error "provider compilation-unit identity differs"
              else if
                Array.exists
                  (fun arg -> List.mem arg [ "-pp"; "-ppx"; "-plugin" ])
                  info.cmt_args
              then
                Error
                  "unresolved compiler-side preprocessing changes the audited emitted \
                   body"
              else if
                info.cmt_source_digest <> Some (Digest.from_hex (emitted_digest owner))
              then
                Error
                  "audited implementation digest differs; re-audit its \
                   construction/codec contract"
              else if
                not
                  (Option.fold ~none:false
                     ~some:(fun source ->
                       source_is (owner.source ^ ".ml") source
                       || source_is (owner.source ^ ".pp.ml") source)
                     info.cmt_sourcefile)
              then Error "provider source ownership differs"
              else
                let () =
                  Array.iter
                    (fun imported ->
                      match Import_info.crc imported with
                      | None -> ()
                      | Some expected -> (
                          let name = Import_info.name imported in
                          let imported_cmi =
                            Cmi_format.read_cmi
                              (Load_path.find
                                 (String.uncapitalize_ascii
                                    (Compilation_unit.Name.to_string name)
                                 ^ ".cmi"))
                          in
                          match
                            Array.find_opt
                              (fun i -> Import_info.has_name i ~name)
                              imported_cmi.cmi_crcs
                          with
                          | Some actual when Import_info.crc actual = Some expected -> ()
                          | _ ->
                              failwith
                                ("audited provider import fingerprint differs: "
                                ^ Compilation_unit.Name.to_string name)))
                    info.cmt_imports
                in
                let cmi = Cmi_format.read_cmi (Load_path.find (filename ^ ".cmi")) in
                let fingerprint imports =
                  Option.bind
                    (Array.find_opt
                       (fun i ->
                         Compilation_unit.Name.to_string (Import_info.name i)
                         = owner.unit_)
                       imports)
                    Import_info.crc
                in
                let cmi_crc = fingerprint cmi.cmi_crcs in
                if cmi_crc = None || fingerprint info.cmt_imports <> cmi_crc then
                  Error "provider implementation/interface fingerprints differ"
                else Ok ()
            with
            | Not_found -> Error "required provider CMT/CMI is missing"
            | Failure message | Sys_error message -> Error message
            | Cmt_format.Error _ | Cmi_format.Error _ ->
                Error "required provider compiler metadata is malformed"
          in
          Hashtbl.add audits owner.unit_ result;
          result
    in
    match decision with
    | Ok () -> true
    | Error reason ->
        fail loc ("required audited evidence for " ^ owner.unit_ ^ ": " ^ reason);
        false
  in
  let raw =
    List.filter_map
      (fun name -> Option.map (fun (p, d) -> (name, p, d.type_uid)) (type_ name))
      raw_names
  in
  let scalars =
    List.filter_map
      (fun name -> Option.map (fun (_, d) -> d.type_uid) (type_ name))
      scalar_names
  in
  let owned_module owner name =
    match String.split_on_char '.' name with
    | _ :: _ :: nested -> String.concat "." (owner.unit_ :: nested)
    | _ -> owner.unit_
  in
  let boundary domain loc d =
    if not (audited domain.owner loc) then false
    else
      let cmi =
        Cmi_format.read_cmi
          (Load_path.find (String.uncapitalize_ascii domain.owner.unit_ ^ ".cmi"))
      in
      (* Env strengthens abstract declarations to self aliases. Check the real CMI's
       unstrengthened declaration, not that synthetic transparent manifest. *)
      let opaque =
        List.exists
          (function
            | Sig_type (_, actual, _, _) when actual.type_uid = d.type_uid -> (
                match (actual.type_kind, actual.type_manifest) with
                | Type_abstract _, None -> true
                | Type_abstract _, Some _ -> actual.type_private = Asttypes.Private
                | _ -> false)
            | _ -> false)
          (fst cmi.cmi_sign)
      in
      if not opaque then
        fail loc "audited domain root no longer has its required opaque/private boundary";
      opaque
  in
  let domain_of d =
    List.find_opt
      (fun domain ->
        declaration_source d domain.owner.source
        && List.exists
             (fun root ->
               match type_ (domain.owner.unit_ ^ "." ^ root) with
               | Some (_, target) -> d.type_uid = target.type_uid
               | None -> false)
             domain.roots)
      domains
  in
  let codec_of d =
    List.find_map
      (fun (owner, module_, names) ->
        if
          public_source owner.source d.val_loc.loc_start.pos_fname
          && List.exists
               (fun name ->
                 match value (owned_module owner module_ ^ "." ^ name) with
                 | Some target -> d.val_uid = target.val_uid
                 | None -> false)
               names
        then Some owner
        else None)
      codecs
  in
  let field_owner uid =
    List.find_map
      (fun (name, labels) ->
        let ownership =
          List.find_map
            (fun (owner, module_, _) ->
              if String.starts_with ~prefix:(module_ ^ ".") name then
                Some
                  ( owner,
                    owned_module owner module_
                    ^ String.sub name (String.length module_)
                        (String.length name - String.length module_) )
              else None)
            codecs
        in
        match Option.bind ownership (fun (_, owned) -> type_ owned) with
        | Some (_, d) -> (
            match d.type_kind with
            | Type_record (members, _, _) ->
                if
                  List.exists
                    (fun member ->
                      member.ld_uid = uid && List.mem (Ident.name member.ld_id) labels)
                    members
                then Option.map fst ownership
                else None
            | _ -> None)
        | None -> None)
      fields
  in
  let json_constructor uid =
    match type_ "Ox_observability__Logger.value" with
    | Some (_, { type_kind = Type_variant (constructors, _, _); _ }) ->
        List.exists (fun c -> c.cd_uid = uid && Ident.name c.cd_id = "Json") constructors
    | _ -> false
  in
  let rec mentions en uids paths nodes ty =
    if List.mem (Types.get_id ty) nodes then false
    else
      let nodes = Types.get_id ty :: nodes in
      match Types.get_desc ty with
      | Tconstr (path, args, _) ->
          let d = Env.find_type path en in
          List.mem d.type_uid uids
          || List.exists (mentions en uids paths nodes) args
          || (not (List.exists (Path.same path) paths))
             &&
             let found = ref false in
             let child ty =
               if mentions en uids (path :: paths) nodes ty then found := true
             in
             Option.iter child d.type_manifest;
             Btype.iter_type_expr_kind child d.type_kind;
             !found
      | _ ->
          let found = ref false in
          Btype.iter_type_expr
            (fun t -> if mentions en uids paths nodes t then found := true)
            ty;
          !found
  in
  let rec walk_type en focus loc produced paths nodes depth ty =
    let focus =
      match Types.get_desc ty with
      | Tconstr (path, _, _) when List.mem (Env.find_type path en).type_uid focus -> []
      | _ -> focus
    in
    if focus <> [] && not (mentions en focus [] [] ty) then ()
    else if depth > 128 then fail loc "published type traversal exceeded its finite bound"
    else if not (List.mem (Types.get_id ty) nodes) then
      let nodes = Types.get_id ty :: nodes in
      let child = walk_type en focus loc produced paths nodes (depth + 1) in
      match Types.get_desc ty with
      | Tvar _ | Tunivar _ -> ()
      | Tarrow (_, arg, result, _) ->
          walk_type en focus loc false paths nodes (depth + 1) arg;
          walk_type en focus loc true paths nodes (depth + 1) result
      | Tconstr (path, args, _) -> (
          List.iter child args;
          let d = Env.find_type path en in
          match
            List.find_opt
              (fun (_, p, uid) ->
                d.type_uid = uid || Path.same (Env.normalize_type_path None en path) p)
              raw
          with
          | Some (name, _, _) ->
              finding loc ("published domain representation contains raw " ^ name)
          | None when List.exists (Path.same path) paths -> ()
          | None -> (
              let paths = path :: paths in
              let apply = Ctype.apply en d.type_params in
              let inspect = walk_type en focus loc produced paths nodes (depth + 1) in
              match d.type_manifest with
              | Some manifest ->
                  Option.iter (fun domain -> ignore (boundary domain loc d)) (domain_of d);
                  inspect (apply manifest args)
              | None -> walk_kind en focus loc produced paths nodes (depth + 1) d args))
      | Tpackage _ ->
          fail loc
            "first-class module representation requires unresolved published evidence"
      | _ -> Btype.iter_type_expr child ty
  and walk_kind en focus loc produced paths nodes depth d args =
    let inspect ty =
      walk_type en focus loc produced paths nodes depth
        (Ctype.apply en d.type_params ty args)
    in
    let label l =
      match field_owner l.ld_uid with
      | Some owner -> ignore (audited owner loc)
      | _ -> inspect l.ld_type
    in
    match d.type_kind with
    | Type_abstract _ -> (
        if produced && d.type_manifest = None && not (List.mem d.type_uid scalars) then
          match domain_of d with
          | Some domain -> ignore (boundary domain loc d)
          | None ->
              fail loc
                "opaque published representation has no proven construction contract")
    | Type_record (labels, _, _) | Type_record_unboxed_product (labels, _, _) ->
        List.iter label labels
    | Type_variant (constructors, _, _) ->
        List.iter
          (fun c ->
            if json_constructor c.cd_uid && audited (List.nth domains 3).owner loc then ()
            else
              match c.cd_args with
              | Cstr_record labels -> List.iter label labels
              | Cstr_tuple arguments ->
                  List.iter (fun arg -> inspect arg.ca_type) arguments)
          constructors
    | Type_open -> fail loc "open published type has unresolved extension representation"
  in
  let inspect en focus loc ty =
    try walk_type en focus loc true [] [] 0 ty with
    | Not_found | Env.Error _ ->
        fail loc "published type owner/definition cannot be resolved"
    | Ctype.Cannot_apply -> fail loc "published alias substitution cannot be resolved"
  in
  let rec publishes en focus loc paths depth mty =
    if depth > 32 then fail loc "published module traversal exceeded its finite bound"
    else
      match Mtype.scrape_alias en mty with
      | Mty_signature signature ->
          let en = Env.add_signature signature en in
          List.iter
            (function
              | Sig_value (id, d, _) ->
                  if focus = [] || mentions en focus [] [] d.val_type then (
                    (match codec_of d with
                    | Some owner -> ignore (audited owner d.val_loc)
                    | _ -> inspect en focus d.val_loc d.val_type);
                    List.iter
                      (fun domain ->
                        let uids =
                          List.filter_map
                            (fun root ->
                              Option.map
                                (fun (_, d) -> d.type_uid)
                                (type_ (domain.owner.unit_ ^ "." ^ root)))
                            domain.roots
                        in
                        let rec returned ty =
                          match Types.get_desc ty with
                          | Tarrow (_, _, result, _) -> returned result
                          | Tpoly (body, _) -> returned body
                          | _ -> mentions en uids [] [] ty
                        in
                        if
                          unit_ = domain.owner.unit_ && returned d.val_type
                          && not
                               (List.exists
                                  (fun name ->
                                    Ident.name id = name
                                    &&
                                    match value (domain.owner.unit_ ^ "." ^ name) with
                                    | Some producer -> producer.val_uid = d.val_uid
                                    | None -> false)
                                  domain.producers)
                        then
                          fail d.val_loc
                            "published producer is outside the audited construction \
                             contract")
                      domains)
              | Sig_type (_, d, _, _) ->
                  if
                    focus = [] || List.mem d.type_uid focus
                    || (let found = ref false in
                        Btype.iter_type_expr_kind
                          (fun t -> if mentions en focus [] [] t then found := true)
                          d.type_kind;
                        !found)
                    || Option.fold ~none:false ~some:(mentions en focus [] [])
                         d.type_manifest
                  then (
                    let focus = if List.mem d.type_uid focus then [] else focus in
                    Option.iter (inspect en focus d.type_loc) d.type_manifest;
                    walk_kind en focus d.type_loc true [] [] 0 d d.type_params)
              | Sig_module (_, _, d, _, _) ->
                  publishes en focus d.md_loc paths (depth + 1) d.md_type
              | Sig_modtype (_, d, _) ->
                  Option.iter (publishes en focus d.mtd_loc paths (depth + 1)) d.mtd_type
              | Sig_typext (_, d, _, _) ->
                  List.iter (inspect en focus d.ext_loc)
                    (Types.tys_of_constr_args d.ext_args)
              | Sig_class (_, d, _, _) ->
                  fail d.cty_loc
                    "published class representation is outside the finite evidence \
                     horizon"
              | Sig_class_type (_, d, _, _) ->
                  fail d.clty_loc
                    "published class representation is outside the finite evidence \
                     horizon"
              | Sig_jkind _ -> ())
            signature
      | Mty_functor (parameter, result, _) ->
          let en =
            match parameter with
            | Unit -> en
            | Named (id, arg, _) ->
                publishes en focus loc paths (depth + 1) arg;
                Option.fold ~none:en
                  ~some:(fun id -> Env.add_module ~arg:true id Mp_present arg en)
                  id
          in
          publishes en focus loc paths (depth + 1) result
      | Mty_strengthen (body, _, _) -> publishes en focus loc paths (depth + 1) body
      | Mty_ident path | Mty_alias path ->
          if List.exists (Path.same path) paths then
            fail loc "recursive/abstract published module owner is unresolved"
          else fail loc "published module signature cannot be resolved"
  in
  (* Source attributes remain obligations even if preprocessing drops them. *)
  let same_marker a b =
    a.Location.loc_start.Lexing.pos_cnum = b.Location.loc_start.Lexing.pos_cnum
    && a.Location.loc_end.Lexing.pos_cnum = b.Location.loc_end.Lexing.pos_cnum
  in
  let source_markers = ref [] in
  let authored = Artifact.authored_source ~caps artifact in
  let source_interface = String.ends_with ~suffix:".mli" authored in
  Syntax.walk ~caps authored (fun _ base ->
      {
        base with
        Ast_iterator.signature =
          (fun self signature ->
            let markers =
              List.filter_map
                (fun item ->
                  match item.Parsetree.psig_desc with
                  | Psig_attribute a when a.attr_name.txt = "ox.domain" -> Some a
                  | _ -> None)
                signature.Parsetree.psg_items
            in
            if source_interface then
              List.iter
                (fun a ->
                  match a.Parsetree.attr_payload with
                  | PStr [] when List.length markers = 1 ->
                      source_markers := a.attr_loc :: !source_markers
                  | _ ->
                      fail a.attr_loc
                        "malformed ox.domain marker; expected one payload-free \
                         interface-local [@@@ox.domain]")
                markers;
            base.signature self signature);
        attribute =
          (fun self a ->
            if
              a.Parsetree.attr_name.txt = "ox.domain"
              && not (List.exists (same_marker a.attr_loc) !source_markers)
            then
              fail a.attr_loc
                "misplaced ox.domain marker; only [@@@ox.domain] in a compiled interface \
                 adds enforcement";
            base.attribute self a);
      });
  Artifact.setup ~caps artifact;
  let base = Tast_iterator.default_iterator in
  let valid_markers = ref [] in
  let signatures = ref [] in
  let interface =
    match artifact.info.cmt_annots with Cmt_format.Interface _ -> true | _ -> false
  in
  let iterator =
    {
      base with
      signature =
        (fun self signature ->
          let markers =
            List.filter_map
              (fun item ->
                match item.Typedtree.sig_desc with
                | Typedtree.Tsig_attribute a when a.attr_name.txt = "ox.domain" -> Some a
                | _ -> None)
              signature.sig_items
          in
          if interface then (
            List.iter
              (fun a ->
                match a.Parsetree.attr_payload with
                | PStr [] when List.length markers = 1 ->
                    valid_markers := a.attr_loc :: !valid_markers
                | _ ->
                    fail a.attr_loc
                      "malformed ox.domain marker; expected one payload-free \
                       interface-local [@@@ox.domain]")
              markers;
            signatures := (signature, markers <> []) :: !signatures);
          base.signature self signature);
      attribute =
        (fun self a ->
          if
            a.Parsetree.attr_name.txt = "ox.domain"
            && not (List.exists (same_marker a.attr_loc) !valid_markers)
          then
            fail a.attr_loc
              "misplaced ox.domain marker; only [@@@ox.domain] in a compiled interface \
               adds enforcement";
          base.attribute self a);
    }
  in
  (match artifact.info.cmt_annots with
  | Cmt_format.Interface tree -> iterator.signature iterator tree
  | Cmt_format.Implementation tree -> iterator.structure iterator tree
  | _ ->
      fail Location.none "complete compiler annotation required for codec-seams evidence");
  List.iter
    (fun loc ->
      if not (List.exists (same_marker loc) !valid_markers) then
        fail loc "source domain marker has no matching typed interface evidence")
    !source_markers;
  List.iter
    (fun (signature, marked) ->
      let is_root =
        match artifact.info.cmt_annots with
        | Cmt_format.Interface root -> root == signature
        | _ -> false
      in
      let own =
        List.find_opt
          (fun domain ->
            is_root && unit_ = domain.owner.unit_
            && public_source domain.owner.source
                 signature.Typedtree.sig_sloc.loc_start.pos_fname)
          domains
      in
      if marked || own <> None then (
        Option.iter (fun domain -> ignore (audited domain.owner signature.sig_sloc)) own;
        try
          let en = Paths.env ~caps signature.sig_final_env in
          Option.iter
            (fun domain ->
              List.iter
                (fun root ->
                  match
                    List.find_opt
                      (function
                        | Sig_type (id, _, _, _) -> Ident.name id = root | _ -> false)
                      signature.sig_type
                  with
                  | Some (Sig_type (_, d, _, _)) -> ignore (boundary domain d.type_loc d)
                  | _ ->
                      fail signature.sig_sloc
                        ("required audited domain type is missing: " ^ root))
                domain.roots)
            own;
          let focus =
            match own with
            | Some domain when (not marked) && not domain.whole ->
                List.filter_map
                  (function
                    | Sig_type (id, d, _, _) when List.mem (Ident.name id) domain.roots ->
                        Some d.type_uid
                    | _ -> None)
                  signature.sig_type
            | _ -> []
          in
          publishes en focus signature.sig_sloc [] 0 (Mty_signature signature.sig_type)
        with
        | Not_found | Env.Error _ | Envaux.Error _ ->
            fail signature.sig_sloc
              "required published compiler ownership cannot be resolved"
        | Ctype.Cannot_apply ->
            fail signature.sig_sloc
              "required published alias substitution cannot be resolved"))
    !signatures
