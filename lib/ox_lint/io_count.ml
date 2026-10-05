(* ^safe-jwwj ^safe-qmcw ^safe-t50j: contracts describe counts, not arbitrary integers. *)
open Ocaml_common
open Typedtree

type semantics = Stream | Socket | Datagram
type shape = Count | Count_address
type contract = { semantics : semantics; shape : shape; arity : int }

let message = function
  | Stream ->
      "stream/descriptor byte count discarded: for streams handle short counts, EOF and \
       zero progress or use an existing complete-transfer interface; for message sockets \
       preserve one-message semantics"
  | Socket ->
      "socket byte count discarded: distinguish stream progress/EOF from datagram \
       length; preserve one-message semantics for datagrams, never loop-until-full"
  | Datagram ->
      "datagram byte count discarded: handle the length of this one message (and \
       possible truncation); do not loop-until-full or split the message"

let count_bindings shape pattern =
  let rec component pattern =
    match pattern.pat_desc with
    | Tpat_var { id; _ } -> [ (id, Count) ]
    | Tpat_alias { pattern = p; id; _ } -> (id, Count) :: component p
    | _ -> []
  in
  let rec whole pattern =
    match pattern.pat_desc with
    | Tpat_tuple ((_, first) :: _) -> component first
    | Tpat_alias { pattern = p; id; _ } -> (id, Count_address) :: whole p
    | Tpat_var { id; _ } -> [ (id, Count_address) ]
    | _ -> []
  in
  match shape with Count -> component pattern | Count_address -> whole pattern

let count_ids shape pattern = List.map fst (count_bindings shape pattern)

let passive_count shape pattern =
  let rec component pattern =
    match pattern.pat_desc with
    | Tpat_any | Tpat_var _ -> true
    | Tpat_alias { pattern; _ } -> component pattern
    | _ -> false
  in
  let rec whole pattern =
    match pattern.pat_desc with
    | Tpat_tuple ((_, first) :: _) -> component first
    | Tpat_alias { pattern; _ } -> whole pattern
    | Tpat_any | Tpat_var _ -> true
    | _ -> false
  in
  match shape with Count -> component pattern | Count_address -> whole pattern

(* Only direct immutable aliases and resolved ignore are neutral uses. Any other
   reference retains the count; this is not heap or general integer dataflow. *)
let retained ~is_ignore bindings expression =
  let found = ref false in
  let aliases = ref bindings in
  let source e =
    match e.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } ->
        List.find_map
          (fun (bound, shape) -> if Ident.same id bound then Some shape else None)
          !aliases
    | _ -> None
  in
  let base = Tast_iterator.default_iterator in
  let walk =
    {
      base with
      expr =
        (fun self e ->
          if not !found then
            match e.exp_desc with
            | Texp_apply (fn, [ (_, Arg (inner, _)) ], _, _, _)
              when is_ignore fn && Option.is_some (source inner) ->
                ()
            | Texp_let (Asttypes.Nonrecursive, bindings, body) ->
                let previous = !aliases in
                let forwarded = ref [] in
                List.iter
                  (fun vb ->
                    match source vb.vb_expr with
                    | Some shape when passive_count shape vb.vb_pat ->
                        forwarded := count_bindings shape vb.vb_pat @ !forwarded
                    | _ -> base.value_binding self vb)
                  bindings;
                aliases := !forwarded @ previous;
                self.expr self body;
                aliases := previous
            | _ -> if Option.is_some (source e) then found := true else base.expr self e);
    }
  in
  walk.expr walk expression;
  !found

let check ~caps ~emit =
  let specs =
    [
      ([ "Unix"; "read" ], Stream, Count, 4);
      ([ "Unix"; "write" ], Stream, Count, 4);
      ([ "Unix"; "single_write" ], Stream, Count, 4);
      ([ "Unix"; "recv" ], Socket, Count, 5);
      ([ "Unix"; "send" ], Socket, Count, 5);
      ([ "Unix"; "recvfrom" ], Datagram, Count_address, 5);
      ([ "Unix"; "sendto" ], Datagram, Count, 6);
      ([ "Stdlib"; "input" ], Stream, Count, 4);
    ]
  in
  let required names =
    match Paths.value ~caps names with
    | Some path -> path
    | None ->
        invalid_arg ("ox-io-count: missing supported operation " ^ String.concat "." names)
  in
  (* A pure compilation unit need not depend on Unix at all. Artifact.setup
     verifies actual imports before this decider runs. Once Unix is present,
     every advertised operation contract is required, not silently dropped. *)
  let unix_available = Option.is_some (Paths.module_ ~caps [ "Unix" ]) in
  let targets =
    List.filter_map
      (fun (names, semantics, shape, arity) ->
        if List.hd names = "Unix" && not unix_available then None
        else Some (required names, { semantics; shape; arity }))
      specs
  in
  let ignores = [ required [ "Stdlib"; "ignore" ] ] in
  let learned = ref [] in
  let ignore_aliases = ref [] in
  let is_ignore expression =
    Paths.is_value ~caps ignores expression
    ||
    match expression.exp_desc with
    | Texp_ident { desc; _ } -> List.exists (Shape.Uid.equal desc.val_uid) !ignore_aliases
    | _ -> false
  in
  let callee expression =
    match expression.exp_desc with
    | Texp_ident { path; desc; _ } -> (
        let path =
          Env.normalize_value_path None (Paths.env ~caps expression.exp_env) path
        in
        match
          List.find_map
            (fun (target, contract) ->
              if Path.same path target then Some contract else None)
            targets
        with
        | Some _ as contract -> contract
        | None ->
            List.find_map
              (fun (uid, contract) ->
                if Shape.Uid.equal uid desc.val_uid then Some contract else None)
              !learned)
    | _ -> None
  in
  let shape_matches contract expression =
    let en = Paths.env ~caps expression.exp_env in
    let integer ty =
      match Types.get_desc (Ctype.expand_head en ty) with
      | Tconstr (p, [], _) ->
          Path.same (Env.normalize_type_path None en p) Predef.path_int
      | _ -> false
    in
    match (contract.shape, Types.get_desc (Ctype.expand_head en expression.exp_type)) with
    | Count, _ -> integer expression.exp_type
    | Count_address, Ttuple ((_, count) :: [ _ ]) -> integer count
    | _ -> false
  in
  let operation expression =
    match expression.exp_desc with
    | Texp_apply (fn, args, _, _, _) -> (
        match callee fn with
        | Some contract
          when List.length args = contract.arity
               && List.for_all (function _, Arg _ -> true | _ -> false) args
               && shape_matches contract expression ->
            Some contract
        | _ -> None)
    | _ -> None
  in
  let forwarding expression =
    match expression.exp_desc with
    | Texp_function { params; body = Tfunction_body body; _ } -> (
        let ids =
          List.concat_map
            (fun param ->
              match param.fp_kind with
              | Tparam_pat pattern -> count_ids Count pattern
              | _ -> [])
            params
        in
        match (body.exp_desc, operation body) with
        | Texp_apply (_, args, _, _, _), Some contract
          when List.for_all
                 (function
                   | _, Arg ({ exp_desc = Texp_ident { path = Path.Pident id; _ }; _ }, _)
                     ->
                       List.exists (Ident.same id) ids
                   | _ -> false)
                 args ->
            Some { contract with arity = List.length params }
        | _ -> None)
    | _ -> callee expression
  in
  let learn vb =
    match vb.vb_pat.pat_desc with
    | Tpat_var { uid; _ } ->
        if is_ignore vb.vb_expr then ignore_aliases := uid :: !ignore_aliases;
        Option.iter
          (fun contract -> learned := (uid, contract) :: !learned)
          (forwarding vb.vb_expr)
    | _ -> ()
  in
  let reported = Hashtbl.create 16 in
  let report expression contract =
    let position = expression.exp_loc.Location.loc_start in
    let key = (position.Lexing.pos_fname, position.Lexing.pos_cnum) in
    if not (Hashtbl.mem reported key) then (
      Hashtbl.add reported key ();
      emit expression.exp_loc (message contract.semantics))
  in
  let base = Tast_iterator.default_iterator in
  {
    base with
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, [ (_, Arg (arg, _)) ], _, _, _) when is_ignore fn ->
            Option.iter (report arg) (operation arg)
        | Texp_let (Asttypes.Nonrecursive, bindings, _) -> List.iter learn bindings
        | _ -> ());
        base.expr self e;
        (* Walking first learns compiler-resolved ignore aliases in the body. *)
        match e.exp_desc with
        | Texp_let (Asttypes.Nonrecursive, bindings, body) ->
            List.iter
              (fun vb ->
                Option.iter
                  (fun contract ->
                    if
                      passive_count contract.shape vb.vb_pat
                      && not
                           (retained ~is_ignore
                              (count_bindings contract.shape vb.vb_pat)
                              body)
                    then report vb.vb_expr contract)
                  (operation vb.vb_expr))
              bindings
        | _ -> ());
    value_binding =
      (fun self vb ->
        learn vb;
        Option.iter
          (fun contract ->
            if
              passive_count contract.shape vb.vb_pat
              && count_ids contract.shape vb.vb_pat = []
            then report vb.vb_expr contract)
          (operation vb.vb_expr);
        base.value_binding self vb);
  }
