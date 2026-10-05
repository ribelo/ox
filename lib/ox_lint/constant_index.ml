(* ^safe-rxya ^safe-d197 ^safe-xd2e: resolved getters, typed literal bounds. *)
open Ocaml_common
open Typedtree

type collection = Array | String | Bytes

let check ~caps ~emit =
  let target names =
    match Paths.value ~caps names with
    | Some path -> [ path ]
    | None ->
        failwith ("constant-index: unresolved standard value " ^ String.concat "." names)
  in
  let getters =
    List.map
      (fun (kind, name) -> (kind, target [ "Stdlib"; name; "get" ]))
      [ (Array, "Array"); (String, "String"); (Bytes, "Bytes") ]
  in
  let of_string = target [ "Stdlib"; "Bytes"; "of_string" ] in
  let bindings = Path.Tbl.create 16 in
  (* Ident stamps distinguish legitimate shadowing. Do not infer a getter from
     Longident spelling, a function type, or an arbitrary wrapper's body. *)
  let rec origin seen e =
    match e.exp_desc with
    | Texp_ident { path; _ } when not (List.exists (Path.same path) seen) -> (
        match Path.Tbl.find_opt bindings path with
        | Some bound -> origin (path :: seen) bound
        | None -> e)
    | _ -> e
  in
  let origin = origin [] in
  let string_length e =
    match (origin e).exp_desc with
    | Texp_constant (Const_string (bytes, _, _)) -> Some (String.length bytes)
    | _ -> None
  in
  let length kind e =
    match (kind, (origin e).exp_desc) with
    | Array, Texp_array (_, _, elements, _) -> Some (List.length elements)
    | String, _ -> string_length e
    | Bytes, Texp_apply (fn, [ (_, Arg (literal, _)) ], _, _, _)
      when Paths.is_value ~caps of_string (origin fn) ->
        string_length literal
    | _ -> None
  in
  let base = Tast_iterator.default_iterator in
  let nesting = ref 0 in
  {
    base with
    structure =
      (fun self tree ->
        if !nesting = 0 then Path.Tbl.clear bindings;
        incr nesting;
        Fun.protect ~finally:(fun () -> decr nesting) (fun () -> base.structure self tree));
    value_binding =
      (fun self binding ->
        base.value_binding self binding;
        match binding.vb_pat.pat_desc with
        | Tpat_var { id; _ } -> Path.Tbl.replace bindings (Path.Pident id) binding.vb_expr
        | _ -> ());
    expr =
      (fun self e ->
        (match e.exp_desc with
        | Texp_apply (fn, [ (_, Arg (collection, _)); (_, Arg (index, _)) ], _, _, _) ->
            Option.iter
              (fun (kind, _) ->
                match (length kind collection, (origin index).exp_desc) with
                | Some length, Texp_constant (Const_int index)
                  when index < 0 || index >= length ->
                    emit e.exp_loc
                      (Printf.sprintf
                         "constant index %d is outside [0, %d): proved %s length %d; \
                          indexing raises a defect, not a result error"
                         index length
                         (match kind with
                         | Array -> "array"
                         | String -> "string byte"
                         | Bytes -> "bytes")
                         length)
                | _ -> ())
              (List.find_opt
                 (fun (_, paths) -> Paths.is_value ~caps paths (origin fn))
                 getters)
        | _ -> ());
        base.expr self e);
  }
