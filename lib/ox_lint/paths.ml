(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j: compare origins, not source names. *)
open Ocaml_common
open Typedtree

let env = Envaux.env_of_only_summary ~allow_missing_modules:false
let lid names = Option.get (Longident.unflatten names)
let optional f = try Some (f ()) with Not_found | Env.Error _ -> None

let value names =
  optional (fun () ->
      let initial = Lazy.force Env.initial in
      let path, _, _ =
        Env.lookup_value ~use:false ~loc:Location.none (lid names) initial
      in
      Env.normalize_value_path None initial path)

let module_ names =
  optional (fun () ->
      let initial = Lazy.force Env.initial in
      let path, _, _ =
        Env.lookup_module ~use:false ~loc:Location.none (lid names) initial
      in
      Env.normalize_module_path None initial path)

let values names = List.filter_map value names
let modules names = List.filter_map module_ names

let is_value targets expression =
  match expression.exp_desc with
  | Texp_ident { path; _ } ->
      let path = Env.normalize_value_path None (env expression.exp_env) path in
      List.exists (Path.same path) targets
  | _ -> false

let in_module targets expression =
  match expression.exp_desc with
  | Texp_ident { path; _ } ->
      let en = env expression.exp_env in
      let rec belongs = function
        | Path.Pdot (parent, _) ->
            let parent = Env.normalize_module_path None en parent in
            List.exists (Path.same parent) targets || belongs parent
        | _ -> false
      in
      belongs (Env.normalize_value_path None en path)
  | _ -> false
