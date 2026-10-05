(* ^nonce-ldtz ^nonce-mjpe: legacy behaviour, evidence and exact node ownership. *)
open Ocaml_common
open Typedtree

(* The iterator API reports locations, not nodes. Give synthetic copies a fresh
   location object with IDENTICAL source coordinates, so wrong-node reports are
   distinguishable without any name, line or location-based admission. *)
let clone_location (loc : Location.t) =
  { loc with Location.loc_ghost = Sys.opaque_identity loc.loc_ghost }

let map_expr change tree =
  let mapper =
    {
      Tast_mapper.default with
      expr =
        (fun self original ->
          let changed = change (Tast_mapper.default.expr self original) in
          if changed == original then changed
          else { changed with exp_loc = clone_location changed.exp_loc });
      value_description =
        (fun self original ->
          let changed = Tast_mapper.default.value_description self original in
          if changed == original then changed
          else { changed with val_loc = clone_location changed.val_loc });
    }
  in
  mapper.structure mapper tree

let operator_name = function
  | { exp_desc = Texp_ident { path; _ }; _ } -> Path.last path
  | _ -> ""

let is_constructor name = function
  | { exp_desc = Texp_construct (_, desc, _, [], _); _ } -> desc.cstr_name = name
  | _ -> false

type category = Magic | Identity
type unsafe_node = Magic_node of expression

let location = function Magic_node expression -> expression.exp_loc
let category = function Magic_node _ -> Magic

let same_node left right =
  match (left, right) with Magic_node left, Magic_node right -> left == right

let exact_multiset expected actual =
  let rec remove wanted prefix = function
    | [] -> None
    | ((kind, loc) as item) :: rest ->
        if kind = fst wanted && loc == snd wanted then Some (List.rev_append prefix rest)
        else remove wanted (item :: prefix) rest
  in
  let rec consume actual = function
    | [] -> actual = []
    | item :: rest -> (
        match remove item [] actual with
        | Some actual -> consume actual rest
        | None -> false)
  in
  consume actual expected

let run ~caps path =
  let artifact = Artifact.read ~caps path in
  Artifact.check ~caps ~source:(Artifact.authored_source ~caps artifact) artifact;
  Artifact.setup ~caps artifact;
  let tree =
    match artifact.info.cmt_annots with
    | Cmt_format.Implementation tree -> tree
    | _ -> failwith "implementation required"
  in
  let original_magic = ref None in
  let baseline =
    {
      Tast_iterator.default_iterator with
      expr =
        (fun self expression ->
          (match expression.exp_desc with
          | Texp_ident { path = Path.Pdot (parent, "magic_many"); _ } ->
              original_magic := Some (parent, expression)
          | _ -> ());
          Tast_iterator.default_iterator.expr self expression);
    }
  in
  baseline.structure baseline tree;
  let obj_parent, original_magic = Option.get !original_magic in
  let originals = [ Magic_node original_magic ] in
  let unsafe_nodes kind tree =
    let nodes = ref [] in
    let scanner =
      {
        Tast_iterator.default_iterator with
        expr =
          (fun self expression ->
            (match expression.exp_desc with
            | Texp_ident { path = Path.Pdot (parent, name); _ }
              when kind = Magic && Path.same parent obj_parent
                   && String.starts_with ~prefix:"magic" name ->
                nodes := Magic_node expression :: !nodes
            | _ -> ());
            Tast_iterator.default_iterator.expr self expression);
      }
    in
    scanner.structure scanner tree;
    List.rev !nodes
  in
  let collect kind factory tree =
    let findings = ref [] in
    let iterator = factory (fun loc -> findings := (kind, loc) :: !findings) in
    iterator.Tast_iterator.structure iterator tree;
    List.rev !findings
  in
  let sites nodes = List.map (fun node -> (category node, location node)) nodes in
  let expected_nodes kind expected unknowns artifact tree =
    let nodes = unsafe_nodes kind tree in
    let admitted =
      unknowns = 0
      && artifact.Artifact.info.cmt_source_digest
         = Some (Digest.from_hex "fe73e6eb236332ccc1f08748ddf88c31")
    in
    let nodes =
      if admitted then
        List.filter (fun node -> not (List.exists (same_node node) originals)) nodes
      else nodes
    in
    if List.length nodes <> expected then
      failwith "harness oracle disagrees with case's semantic finding cardinality";
    nodes
  in
  if
    not
      (exact_multiset
         (sites [ Magic_node original_magic ])
         (collect Magic (Concurrency.obj_magic ~caps) tree))
  then failwith "legacy factory must report the exact real guard cast";
  let cases = ref 0 in
  let expect label expected unknowns artifact tree =
    let undecided = ref 0 and reasons = ref [] in
    let findings =
      collect Magic
        (Concurrency.obj_magic_artifact ~caps ~artifact ~undecided:(fun _ message ->
             reasons := message :: !reasons;
             incr undecided))
        tree
    in
    let wanted = sites (expected_nodes Magic expected unknowns artifact tree) in
    if (not (exact_multiset wanted findings)) || !undecided <> unknowns then
      failwith
        (Printf.sprintf
           "%s: exact physical-node/location multiset mismatch; expected %d/%d, got \
            %d/%d: %s"
           label expected unknowns (List.length findings) !undecided
           (String.concat "; " !reasons));
    incr cases
  in
  let with_info info = { artifact with Artifact.info } in
  let with_tree tree =
    with_info { artifact.info with cmt_annots = Cmt_format.Implementation tree }
  in
  expect "fresh real guard" 0 0 artifact tree;
  expect "unrelated cloned expressions with identical source locations" 1 0 artifact
    (map_expr
       (fun expression -> { expression with exp_loc = clone_location expression.exp_loc })
       tree);
  List.iter
    (fun flag ->
      expect ("unknown transform " ^ flag) 1 1
        (with_info
           {
             artifact.info with
             cmt_args = Array.append artifact.info.cmt_args [| flag; "unreviewed" |];
           })
        tree)
    [ "-pp"; "-ppx"; "-plugin"; "-as-ppx" ];
  expect "changed source or extra authored cast" 1 0
    (with_info
       { artifact.info with cmt_source_digest = Some (Digest.string "altered source") })
    tree;
  expect "absent implementation source digest" 1 0
    (with_info { artifact.info with cmt_source_digest = None })
    tree;
  expect "mismatched implementation interface digest" 1 1
    (with_info
       {
         artifact.info with
         cmt_interface_digest = Some (Digest.string "wrong signature");
       })
    tree;
  expect "wrong compiler owner" 1 1
    (with_info
       {
         artifact.info with
         cmt_modname = Compilation_unit.of_string "Not_the_public_once";
       })
    tree;
  let missing_contract =
    Array.of_list
      (List.filter
         (fun imported ->
           not
             (Import_info.has_name imported
                ~name:(Compilation_unit.name artifact.info.cmt_modname)))
         (Array.to_list artifact.info.cmt_imports))
  in
  expect "absent implementation self-import contract" 1 1
    (with_info { artifact.info with cmt_imports = missing_contract })
    tree;
  List.iter
    (fun name ->
      let changed =
        map_expr
          (fun expr ->
            match expr.exp_desc with
            | Texp_ident ident when operator_name expr = name ->
                {
                  expr with
                  exp_desc =
                    Texp_ident
                      {
                        ident with
                        path = Path.Pident (Ident.create_local ("fake_" ^ name));
                      };
                }
            | _ -> expr)
          tree
      in
      (* A shadowed cast is not a genuine Stdlib.Obj identifier: the required
         unknown is the fail-closed outcome, rather than a fabricated finding. *)
      expect ("shadowed operator " ^ name)
        (if name = "magic_many" then 0 else 1)
        1 (with_tree changed) changed)
    [ "magic_many"; "make"; "exchange"; "invalid_arg" ];
  let literal name =
    let found = ref None in
    let iterator =
      {
        Tast_iterator.default_iterator with
        expr =
          (fun self expr ->
            if is_constructor name expr then found := Some expr;
            Tast_iterator.default_iterator.expr self expr);
      }
    in
    iterator.structure iterator tree;
    match !found with
    | Some expr -> expr
    | None -> failwith ("missing real literal " ^ name)
  in
  let mutate label change =
    let changed = map_expr change tree in
    expect label 1 1 (with_tree changed) changed
  in
  let false_ = literal "false" and true_ = literal "true" in
  mutate "inverted initial flag" (fun expr ->
      if is_constructor "false" expr then true_ else expr);
  mutate "exchange no longer consumes flag" (fun expr ->
      if is_constructor "true" expr then false_ else expr);
  mutate "reversed guard branches" (fun expr ->
      match expr.exp_desc with
      | Texp_ifthenelse (test, yes, Some no) ->
          { expr with exp_desc = Texp_ifthenelse (test, no, Some yes) }
      | _ -> expr);
  mutate "removed atomic flag binding" (fun expr ->
      match expr.exp_desc with
      | Texp_let (Asttypes.Nonrecursive, [ binding ], body) -> (
          match binding.vb_expr.exp_desc with
          | Texp_apply (fn, _, _, _, _) when operator_name fn = "make" -> body
          | _ -> expr)
      | _ -> expr);
  mutate "returned cast rather than entering callback" (fun expr ->
      match expr.exp_desc with
      | Texp_apply
          (({ exp_desc = Texp_ident { path = Path.Pident id; _ }; _ } as fn), _, _, _, _)
        when Ident.name id = "f" ->
          fn
      | _ -> expr);
  mutate "non-native callback input" (fun expr ->
      match expr.exp_desc with
      | Texp_function ({ params = [ param ]; _ } as fn) -> (
          match param.fp_kind with
          | Tparam_pat ({ pat_desc = Tpat_var variable; _ } as pat)
            when Ident.name variable.id = "f" ->
              {
                expr with
                exp_desc =
                  Texp_function
                    {
                      fn with
                      params =
                        [
                          {
                            param with
                            fp_kind = Tparam_pat { pat with pat_type = Predef.type_int };
                          };
                        ];
                    };
              }
          | _ -> expr)
      | _ -> expr);
  mutate "unreviewed unique-mode cast" (fun expr ->
      match expr.exp_desc with
      | Texp_ident ({ path = Path.Pdot (parent, "magic_many"); _ } as ident) ->
          {
            expr with
            exp_desc = Texp_ident { ident with path = Path.Pdot (parent, "magic_unique") };
          }
      | _ -> expr);
  mutate "labelled guard or returned closure" (fun expr ->
      match expr.exp_desc with
      | Texp_function ({ params = [ param ]; _ } as fn) ->
          {
            expr with
            exp_desc =
              Texp_function
                {
                  fn with
                  params =
                    [ { param with fp_arg_label = Labelled "not_the_native_guard" } ];
                };
          }
      | _ -> expr);
  mutate "non-native returned unit parameter" (fun expr ->
      match expr.exp_desc with
      | Texp_function ({ params = [ param ]; _ } as fn) -> (
          match param.fp_kind with
          | Tparam_pat ({ pat_desc = Tpat_construct (_, desc, _, [], _); _ } as pat)
            when desc.cstr_name = "()" ->
              {
                expr with
                exp_desc =
                  Texp_function
                    {
                      fn with
                      params =
                        [
                          {
                            param with
                            fp_kind = Tparam_pat { pat with pat_type = Predef.type_int };
                          };
                        ];
                    };
              }
          | _ -> expr)
      | _ -> expr);
  let extra = { tree with str_items = tree.str_items @ tree.str_items } in
  expect "extra cast within pinned typed implementation" 2 1 (with_tree extra) extra;

  List.iter
    (fun name ->
      mutate ("forged canonical operator UID " ^ name) (fun expression ->
          match expression.exp_desc with
          | Texp_ident ident when operator_name expression = name ->
              {
                expression with
                exp_desc =
                  Texp_ident
                    {
                      ident with
                      desc =
                        {
                          ident.desc with
                          val_uid = Shape.Uid.internal_not_actually_unique;
                        };
                    };
              }
          | _ -> expression))
    [ "magic_many"; "make"; "exchange"; "invalid_arg" ];
  let original_item = List.hd tree.str_items in
  let extra_expression expression =
    match original_item.str_desc with
    | Tstr_value (recursion, [ binding ]) ->
        {
          original_item with
          str_desc = Tstr_value (recursion, [ { binding with vb_expr = expression } ]);
        }
    | _ -> failwith "single guard required"
  in
  let clone = { original_magic with exp_loc = clone_location original_magic.exp_loc } in
  if clone.exp_loc <> original_magic.exp_loc || clone.exp_loc == original_magic.exp_loc
  then failwith "optimizer-resistant identical-coordinate clone required";
  let site = [ (Magic, clone.exp_loc) ] in
  let red label expected wrong =
    if List.length expected <> List.length wrong || exact_multiset expected wrong then
      failwith ("oracle accepted same-count wrong-node/category: " ^ label)
  in
  red "clone at original location" site [ (Magic, original_magic.exp_loc) ];
  red "duplicate at original location" (site @ site)
    (site @ [ (Magic, original_magic.exp_loc) ]);
  red "right location wrong category" site [ (Identity, clone.exp_loc) ];
  red "right duplicate locations wrong category" (site @ site)
    (site @ [ (Identity, clone.exp_loc) ]);
  let clone_item = extra_expression clone in
  let extra = { tree with str_items = tree.str_items @ [ clone_item ] } in
  expect "same-coordinate clone reported; only original admitted" 1 0 artifact extra;
  let duplicate = { tree with str_items = extra.str_items @ [ clone_item ] } in
  expect "duplicate clone reports preserved as an exact multiset" 2 0 artifact duplicate;
  let unique =
    {
      clone with
      exp_desc =
        (match clone.exp_desc with
        | Texp_ident ident ->
            Texp_ident { ident with path = Path.Pdot (obj_parent, "magic_unique") }
        | _ -> assert false);
    }
  in
  expect "unrelated unique cast keeps original physical admission" 1 0 artifact
    { tree with str_items = tree.str_items @ [ extra_expression unique ] };
  let copy source target =
    let bytes =
      Ox_caps.Cap_stdlib.In_channel.with_open_bin ~caps source In_channel.input_all
    in
    Ox_caps.Cap_stdlib.Out_channel.with_open_bin ~caps target (fun channel ->
        Out_channel.output_string channel bytes)
  in
  copy path "guard_evidence.cmt";
  let created = ref false in
  Fun.protect
    ~finally:(fun () ->
      Ox_caps.Cap_unix.unlink ~caps "guard_evidence.cmt";
      if !created then Ox_caps.Cap_unix.unlink ~caps "guard_evidence.cmti")
    (fun () ->
      let copied = { artifact with path = "guard_evidence.cmt" } in
      expect "missing public companion" 1 1 copied tree;
      copy path "guard_evidence.cmti";
      created := true;
      expect "wrong companion native payload" 1 1 copied tree);
  Ox_caps.Cap_stdlib.printf ~caps
    "Global Once artifact adapter: legacy finding preserved; %d exact-node \
     evidence/ownership cases;4 same-count wrong-node/category red controls passed\n"
    !cases

let aliases ~caps path =
  let artifact = Artifact.read ~caps path in
  Artifact.check ~caps ~source:(Artifact.authored_source ~caps artifact) artifact;
  Artifact.setup ~caps artifact;
  let tree =
    match artifact.info.cmt_annots with
    | Cmt_format.Implementation tree -> tree
    | _ -> failwith "aliases implementation required"
  in
  let environment = Lazy.force Env.initial in
  let canonical name =
    let _, value, _ =
      Env.lookup_value ~use:false ~loc:Location.none
        (Paths.lid ("Stdlib", [ "Obj"; name ]))
        environment
    in
    value.Types.val_uid
  in
  let uids = List.map canonical [ "magic"; "magic_many" ] in
  let wanted = ref [] in
  let independent =
    {
      Tast_iterator.default_iterator with
      expr =
        (fun self expression ->
          (match expression.exp_desc with
          | Texp_ident { desc; _ } when List.exists (Shape.Uid.equal desc.val_uid) uids ->
              wanted := (Magic, expression.exp_loc) :: !wanted
          | _ -> ());
          Tast_iterator.default_iterator.expr self expression);
    }
  in
  independent.structure independent tree;
  if List.length !wanted <> 4 then
    failwith "four independently owned alias casts required";
  let check factory =
    let reports = ref [] in
    let iterator = factory (fun location -> reports := (Magic, location) :: !reports) in
    iterator.Tast_iterator.structure iterator tree;
    if not (exact_multiset !wanted !reports) then
      failwith "canonical alias/shadow exact-node oracle mismatch"
  in
  check (Concurrency.obj_magic ~caps);
  check
    (Concurrency.obj_magic_artifact ~caps ~artifact ~undecided:(fun _ why ->
         failwith ("unreviewed ordinary alias artifact undecided: " ^ why)));
  Ox_caps.Cap_stdlib.printf ~caps
    "Global alias controls: two exact native scans; four canonical casts reported, local \
     Obj/Stdlib shadows clean\n"

let () =
  let powerbox = Ox_test.powerbox () in
  let caps =
    (powerbox :> < Ox_caps.Cap.fs_read ; Ox_caps.Cap.fs_write ; Ox_caps.Cap.stdout >)
  in
  match Array.to_list Sys.argv with
  | [ _; path; alias ] ->
      run ~caps path;
      aliases ~caps alias
  | _ -> failwith "usage: test_global_adapter GUARD_CMT ALIAS_CMT"
