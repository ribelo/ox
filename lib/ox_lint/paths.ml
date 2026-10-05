(* ^nlintc-du4v ^nlintc-g6k3 ^nlintc-j03j: compare origins, not source names. *)
open Ocaml_common
open Ox_caps
open Typedtree

let env ~(caps : < Cap.fs_read ; .. >) en =
  ignore caps#fs_read;
  Envaux.env_of_only_summary ~allow_missing_modules:false en

(* ^safe-3osb: a compiler name carries its first lexical component. *)
type name = string * string list

let lid (head, tail) =
  List.fold_left
    (fun path name ->
      Longident.Ldot
        ( { Location.txt = path; loc = Location.none },
          { Location.txt = name; loc = Location.none } ))
    (Longident.Lident head) tail

let optional f = try Some (f ()) with Not_found | Env.Error _ -> None

let value ~(caps : < Cap.fs_read ; .. >) names =
  ignore caps#fs_read;
  optional (fun () ->
      let initial = Lazy.force Env.initial in
      let path, _, _ =
        Env.lookup_value ~use:false ~loc:Location.none (lid names) initial
      in
      Env.normalize_value_path None initial path)

let module_ ~(caps : < Cap.fs_read ; .. >) names =
  ignore caps#fs_read;
  optional (fun () ->
      let initial = Lazy.force Env.initial in
      let path, _, _ =
        Env.lookup_module ~use:false ~loc:Location.none (lid names) initial
      in
      Env.normalize_module_path None initial path)

let values ~(caps : < Cap.fs_read ; .. >) names = List.filter_map (value ~caps) names
let modules ~(caps : < Cap.fs_read ; .. >) names = List.filter_map (module_ ~caps) names

let is_value ~(caps : < Cap.fs_read ; .. >) targets expression =
  match expression.exp_desc with
  | Texp_ident { path; _ } ->
      let path = Env.normalize_value_path None (env ~caps expression.exp_env) path in
      List.exists (Path.same path) targets
  | _ -> false

let in_module ~(caps : < Cap.fs_read ; .. >) targets expression =
  match expression.exp_desc with
  | Texp_ident { path; _ } ->
      let en = env ~caps expression.exp_env in
      let rec belongs = function
        | Path.Pdot (parent, _) ->
            let parent = Env.normalize_module_path None en parent in
            List.exists (Path.same parent) targets || belongs parent
        | _ -> false
      in
      belongs (Env.normalize_value_path None en path)
  | _ -> false
