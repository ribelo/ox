(* ^nlint-hxar ^nlint-emql: the first typed rule, from the measured spike. *)
open Ocaml_common
open Typedtree

type t = {
  id : string;
  message : string;
  violating : string;
  clean : string;
  documentation : string;
  source :
    ((Location.t -> unit) ->
    Syntax.context ->
    Ast_iterator.iterator ->
    Ast_iterator.iterator)
    option;
  typed : ((Location.t -> unit) -> Tast_iterator.iterator) option;
}

let env = Envaux.env_of_only_summary ~allow_missing_modules:false
let lid names = Option.get (Longident.unflatten names)

let discarded_result emit =
  let initial = Lazy.force Env.initial in
  let result, _ =
    Env.lookup_type ~use:false ~loc:Location.none (lid [ "Stdlib"; "result" ]) initial
  in
  let result = Env.normalize_type_path None initial result in
  let ignore, _, _ =
    Env.lookup_value ~use:false ~loc:Location.none (lid [ "Stdlib"; "ignore" ]) initial
  in
  let ignore = Env.normalize_value_path None initial ignore in
  let report loc e =
    let en = env e.exp_env in
    match Types.get_desc (Ctype.expand_head en e.exp_type) with
    | Tconstr (path, [ _; _ ], _)
      when Path.same (Env.normalize_type_path None en path) result ->
        emit loc
    | _ -> ()
  in
  let base = Tast_iterator.default_iterator in
  {
    base with
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, args, _, _, _) -> (
            match fn.exp_desc with
            | Texp_ident { path; _ }
              when Path.same (Env.normalize_value_path None (env fn.exp_env) path) ignore
              ->
                List.iter
                  (function _, Arg (arg, _) -> report e.exp_loc arg | _ -> ())
                  args
            | _ -> ())
        | _ -> ());
        base.expr self e);
    value_binding =
      (fun self vb ->
        (match vb.vb_pat.pat_desc with
        | Tpat_any -> report vb.vb_pat.pat_loc vb.vb_expr
        | _ -> ());
        base.value_binding self vb);
  }

(* ^nlintc-7be1: implementations may hide exceptions; signatures expose them. *)
let public_exception emit _context (base : Ast_iterator.iterator) =
  {
    base with
    Ast_iterator.signature_item =
      (fun self item ->
        (match item.Parsetree.psig_desc with
        | Psig_exception _ -> emit item.psig_loc
        | _ -> ());
        base.signature_item self item);
  }

let concurrency_rule name message typed =
  {
    id = "ox-" ^ name;
    message;
    violating =
      "test/lint/violating/"
      ^ String.map (fun c -> if c = '-' then '_' else c) name
      ^ ".ml";
    clean =
      "test/lint/clean/" ^ String.map (fun c -> if c = '-' then '_' else c) name ^ ".ml";
    documentation = "docs/rules/ox-" ^ name ^ ".md";
    source = None;
    typed = Some typed;
  }

(* ^ncapslint-nf4t ^ncapslint-snhg: one registry and one fixture/page triangle. *)
let capability_rule name typed =
  {
    id = "ox-caps-" ^ name;
    message =
      (if name = "signature" then
         "dangerous operation without its capability in the function signature"
       else
         "raw " ^ name ^ " operation; take its capability and use Ox_caps (docs/caps.md)");
    violating =
      "test/caps/rules/violating/"
      ^ String.map (fun c -> if c = '-' then '_' else c) name
      ^ ".ml";
    clean =
      "test/caps/rules/clean/"
      ^ String.map (fun c -> if c = '-' then '_' else c) name
      ^ ".ml";
    documentation = "docs/rules/ox-caps-" ^ name ^ ".md";
    source = (if name = "signature" then None else Some (Caps.source name));
    typed = Some typed;
  }

(* ^nlintd-z5p5 ^nlintd-vneh: interfaces use the same fixture/page registry. *)
let interface_rule name message typed =
  let rule = concurrency_rule name message typed in
  {
    rule with
    violating = Filename.remove_extension rule.violating ^ ".mli";
    clean = Filename.remove_extension rule.clean ^ ".mli";
  }

let all =
  List.map
    (fun (op : Caps.operation) -> capability_rule op.name (Caps.raw op.name))
    Caps.operations
  @ [ capability_rule "signature" Caps.signature ]
  @ [
      {
        id = "ox-discarded-result";
        message =
          "discarded result; match Ok/Error, propagate the error, or name an intentional \
           discard with a reason";
        violating = "test/lint/violating/discard.ml";
        clean = "test/lint/clean/discard.ml";
        documentation = "docs/rules/ox-discarded-result.md";
        source = None;
        typed = Some discarded_result;
      };
      concurrency_rule "catch-all"
        "cancellation swallowed; re-raise Eio.Cancel.Cancelled or return the original \
         exception as data"
        Concurrency.catch_all;
      concurrency_rule "suspending-finalizer"
        "unprotected suspension in cleanup; wrap the suspension in Eio.Cancel.protect or \
         use Eio.Switch.on_release"
        Concurrency.suspending_finalizer;
      concurrency_rule "stdlib-lock"
        "domain-blocking Stdlib lock; use a fiber-aware Eio.Mutex/Condition/Semaphore \
         (Ox.Mutex when row 65 lands)"
        Concurrency.stdlib_lock;
      concurrency_rule "raw-concurrency"
        "raw Eio concurrency; use Scope.fork @ once, Spawner.t or Ox.Mutex when rows \
         61/64/65 land"
        Concurrency.raw_concurrency;
      {
        id = "ox-public-exception";
        message =
          "public exception; hide the exception and expose a result-returning boundary";
        violating = "test/lint/violating/public_exception.mli";
        clean = "test/lint/clean/public_exception.mli";
        documentation = "docs/rules/ox-public-exception.md";
        source = Some public_exception;
        typed = None;
      };
      concurrency_rule "obj-magic"
        "unchecked Obj.magic* cast; use a typed representation or confine the trusted \
         cast to lib/ox/once.ml"
        Concurrency.obj_magic;
      concurrency_rule "race-deadline"
        "race against sleep is not a deadline (race selects first success); use \
         Ox.Timeout.timeout"
        Concurrency.race_deadline;
      interface_rule "val-behaviour"
        "resource-bearing val needs Suspension, Cancellation, Finalizers and Locking \
         sentences (docs/rules/interface-documentation.md)"
        Interface_docs.behaviour;
      interface_rule "cancel-safety"
        "cancellable val needs Cancellation safety: safe to re-run / unsafe because data \
         is lost / unsafe because progress is lost \
         (docs/rules/interface-documentation.md)"
        Interface_docs.cancel_safety;
    ]

(* ^nlintc-j03j ^nlintc-7be1: narrowly authorised existing boundaries, never suffix matches. *)
let allowances =
  [
    ( "ox-stdlib-lock",
      "lib/sql/sqlite.ml",
      "Guards SQLite C calls contended by system threads." );
    ( "ox-stdlib-lock",
      "lib/ipc/listener.ml",
      "Guards a Hashtbl synchronously, without yielding." );
    ( "ox-public-exception",
      "lib/sql/ox_sql.mli",
      "Existing public SQL exception API is used by inn; migration requires a \
       consumer-coordinated row." );
    ( "ox-public-exception",
      "lib/sql/types.mli",
      "Existing SQL Types exception API must remain compatible with inn." );
    ( "ox-public-exception",
      "lib/sql/sqlite.mli",
      "Existing SQLite exception API requires an inn-compatible consumer migration." );
    ( "ox-public-exception",
      "lib/sql_dsl/ox_sql_dsl_query.mli",
      "Existing SQL query exception API requires an inn-compatible consumer migration." );
    ( "ox-public-exception",
      "lib/sql_dsl/ox_sql_dsl.mli",
      "Existing SQL DSL exception API must remain compatible with inn." );
    ( "ox-public-exception",
      "lib/http/tls_flow.mli",
      "Existing TLS exception API must remain compatible with consumers." );
    ( "ox-obj-magic",
      "lib/ox/once.ml",
      "Reserved trusted ownership casts for row 61; the file does not yet exist." );
  ]

let applies ~root ~source rule =
  let absolute path =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  let normalize path =
    let rec loop acc = function
      | [] -> "/" ^ String.concat "/" (List.rev acc)
      | "" :: rest | "." :: rest -> loop acc rest
      | ".." :: rest -> loop (match acc with [] -> [] | _ :: xs -> xs) rest
      | x :: rest -> loop (x :: acc) rest
    in
    loop [] (String.split_on_char '/' (absolute path))
  in
  rule.id <> "ox-raw-concurrency"
  && ((not
         (List.mem rule.id
            [ "ox-public-exception"; "ox-val-behaviour"; "ox-cancel-safety" ]))
     || Filename.check_suffix source ".mli")
  && not
       (List.exists
          (fun (id, path, _) ->
            id = rule.id && normalize source = normalize (Filename.concat root path))
          allowances)

let select ids =
  List.iter
    (fun id ->
      if not (List.exists (fun rule -> rule.id = id) all) then
        invalid_arg ("unknown rule " ^ id))
    ids;
  List.filter (fun rule -> ids = [] || List.mem rule.id ids) all

let self_check ~root rules =
  List.concat_map
    (fun rule ->
      let missing field path =
        if
          path = ""
          || (not (Sys.file_exists (Filename.concat root path)))
          || Sys.is_directory (Filename.concat root path)
        then [ rule.id ^ ": missing " ^ field ^ " " ^ path ]
        else []
      in
      (if String.trim rule.message = "" then [ rule.id ^ ": missing replacement message" ]
       else [])
      @ missing "violating fixture" rule.violating
      @ missing "clean fixture" rule.clean
      @ missing "documentation" rule.documentation)
    rules
