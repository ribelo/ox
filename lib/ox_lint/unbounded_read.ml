(* ^safe-sx2y ^safe-5ajg ^safe-88rt: finite budgets, authenticated compiler identities. *)
open Ocaml_common
open Typedtree

let check ~(caps : < Ox_caps.Cap.fs_read ; .. >) ~emit ~undecided =
  let identities names =
    ignore caps#fs_read;
    List.filter_map
      (fun name ->
        try
          let _, value, _ =
            Env.lookup_value ~use:false ~loc:Location.none (Paths.lid name)
              (Lazy.force Env.initial)
          in
          Some value.Types.val_uid
        with Not_found | Env.Error _ -> None)
      names
  in
  let eio names = identities [ ("Eio", names) ] in
  let read_all = eio [ "Flow"; "read_all" ] in
  let take_all = eio [ "Buf_read"; "take_all" ] in
  let of_flow = eio [ "Buf_read"; "of_flow" ] in
  let of_string = eio [ "Buf_read"; "of_string" ] in
  let parse = eio [ "Buf_read"; "parse" ] @ eio [ "Buf_read"; "parse_exn" ] in
  let process = eio [ "Process"; "parse_out" ] in
  let max_int = identities [ ("Stdlib", [ "max_int" ]) ] in
  let body_reads =
    identities
      [ ("Cohttp_eio", [ "Body"; "to_string" ]); ("Piaf", [ "Body"; "to_string" ]) ]
  in
  let bindings = ref [] in
  let base = Tast_iterator.default_iterator in
  let rec resolve seen expression =
    match expression.exp_desc with
    | Texp_ident { path = Path.Pident id; _ } -> (
        if List.exists (Ident.same id) seen then expression
        else
          match List.find_opt (fun (other, _) -> Ident.same id other) !bindings with
          | Some (_, target) -> resolve (id :: seen) target
          | None -> expression)
    | _ -> expression
  in
  let known targets expression =
    match (resolve [] expression).exp_desc with
    | Texp_ident { desc; _ } -> List.exists (Types.Uid.equal desc.val_uid) targets
    | _ -> false
  in
  let args arguments =
    List.filter_map
      (function label, Arg (value, _) -> Some (label, value) | _ -> None)
      arguments
  in
  let budget arguments =
    List.exists
      (function
        | (Labelled "max_size" | Optional "max_size"), value -> not (known max_int value)
        | _ -> false)
      arguments
  in
  let rec reader seen expression =
    let expression = resolve [] expression in
    if List.exists (fun other -> other == expression) seen then false
    else
      match expression.exp_desc with
      | Texp_apply (fn, arguments, _, _, _) when known of_flow fn ->
          budget (args arguments)
      | Texp_apply (fn, _, _, _, _) when known of_string fn -> true
      | Texp_let (_, _, body) -> reader (expression :: seen) body
      | _ -> false
  in
  let finding loc =
    emit loc
      "whole-stream read has no finite local budget; use max_size or a bounded body API"
  in
  let visitor =
    {
      base with
      expr =
        (fun self expression ->
          (match expression.exp_desc with
          | Texp_apply (fn, arguments, _, _, _) ->
              let arguments = args arguments in
              if known read_all fn || known body_reads fn then finding expression.exp_loc;
              if known of_flow fn && not (budget arguments) then
                finding expression.exp_loc;
              (if known take_all fn then
                 match List.find_opt (fun (label, _) -> label = Nolabel) arguments with
                 | Some (_, input) when reader [] input -> ()
                 | Some (_, input) -> (
                     match (resolve [] input).exp_desc with
                     | Texp_apply (producer, _, _, _, _) when known of_flow producer -> ()
                     | _ ->
                         undecided expression.exp_loc
                           "take_all reader budget is supplied outside this function")
                 | None -> ());
              List.iter
                (fun (_, parser) ->
                  if known take_all parser then
                    if known process fn || (known parse fn && not (budget arguments)) then
                      finding parser.exp_loc
                    else if not (known parse fn) then
                      undecided parser.exp_loc
                        "higher-order take_all owner has no local budget evidence")
                arguments
          | _ -> ());
          base.expr self expression);
    }
  in
  let gather =
    {
      base with
      value_binding =
        (fun self binding ->
          (match binding.vb_pat.pat_desc with
          | Tpat_var { id; _ } -> bindings := (id, binding.vb_expr) :: !bindings
          | _ -> ());
          base.value_binding self binding);
    }
  in
  let gathered = ref false in
  {
    visitor with
    structure =
      (fun self tree ->
        if not !gathered then (
          gathered := true;
          gather.structure gather tree);
        visitor.structure self tree);
  }
