(** See [Derive.mli]. Pure text preprocessor: parse with the compiler's own parser, blank
    the attribute spans, splice the generated converters in after each declaration. *)

open Ocaml_common

exception Fail of string
(** Internal control flow: raised for any unsupported shape and turned into [Error] at the
    [process] boundary. Never escapes this module. *)

let failf fmt = Printf.ksprintf (fun message -> raise (Fail message)) fmt

(* ---------- Small text utilities ---------- *)

let has_substring needle haystack =
  let needle_len = String.length needle in
  let hay_len = String.length haystack in
  if needle_len = 0 then true
  else if needle_len > hay_len then false
  else
    let found = ref false in
    let i = ref 0 in
    while (not !found) && !i + needle_len <= hay_len do
      if String.sub haystack !i needle_len = needle then found := true;
      incr i
    done;
    !found

let is_blank_char = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let slice source loc =
  let start = loc.Location.loc_start.pos_cnum in
  let stop = loc.Location.loc_end.pos_cnum in
  String.sub source start (stop - start)

let escape_filename filename =
  let buf = Buffer.create (String.length filename) in
  String.iter
    (function
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | c -> Buffer.add_char buf c)
    filename;
  Buffer.contents buf

(* ---------- Attribute analysis ---------- *)

type deriving = Yojson | Other of string | Complex

let classify_deriving_payload (payload : Parsetree.payload) : deriving =
  match payload with
  | Parsetree.PStr
      [
        {
          Parsetree.pstr_desc =
            Parsetree.Pstr_eval
              ( {
                  Parsetree.pexp_desc =
                    Parsetree.Pexp_ident { txt = Longident.Lident name; _ };
                  _;
                },
                _ );
          _;
        };
      ] ->
      if name = "yojson" then Yojson else Other name
  | _ -> Complex

let is_deriving (attr : Parsetree.attribute) =
  match attr.Parsetree.attr_name with { txt = "deriving"; _ } -> true | _ -> false

(** The source span of a whole attribute, from the opening brackets to the closing one:
    [[@@deriving yojson]] (one expression payload) and payload-less attributes like
    [[@@yojson.allow_extra_fields]]. Anything unexpected is a loud failure rather than a
    guessed span. *)
let attribute_span ~source (attr : Parsetree.attribute) : int * int =
  let payload_end =
    match attr.Parsetree.attr_payload with
    | Parsetree.PStr [] -> attr.Parsetree.attr_name.loc.Location.loc_end.pos_cnum
    | Parsetree.PStr [ { Parsetree.pstr_desc = Parsetree.Pstr_eval (expr, _); _ } ] ->
        expr.Parsetree.pexp_loc.Location.loc_end.pos_cnum
    | _ -> failf "unsupported attribute payload"
  in
  let name_start = attr.Parsetree.attr_name.loc.Location.loc_start.pos_cnum in
  let open_start =
    let i = ref name_start in
    while !i > 0 && is_blank_char source.[!i - 1] do
      decr i
    done;
    if !i >= 3 && String.sub source (!i - 3) 3 = "[@@" then !i - 3
    else failf "could not find the opening of an attribute"
  in
  let close_end =
    let n = String.length source in
    let j = ref payload_end in
    while !j < n && is_blank_char source.[!j] do
      incr j
    done;
    if !j < n && source.[!j] = ']' then !j + 1
    else failf "could not find the closing of an attribute"
  in
  (open_start, close_end)

let string_of_key_payload (attr : Parsetree.attribute) : string option =
  match attr.Parsetree.attr_payload with
  | Parsetree.PStr
      [
        {
          Parsetree.pstr_desc =
            Parsetree.Pstr_eval
              ( {
                  Parsetree.pexp_desc =
                    Parsetree.Pexp_constant
                      { Parsetree.pconst_desc = Parsetree.Pconst_string (name, _, _); _ };
                  _;
                },
                _ );
          _;
        };
      ] ->
      Some name
  | _ -> None

let expr_of_default_payload ~source (attr : Parsetree.attribute) : string option =
  match attr.Parsetree.attr_payload with
  | Parsetree.PStr [ { Parsetree.pstr_desc = Parsetree.Pstr_eval (expr, _); _ } ] ->
      Some (slice source expr.Parsetree.pexp_loc)
  | _ -> None

(** [[@@yojson.allow_extra_fields]] on a type declaration: the decoded record then ignores
    object fields its type does not name. A payload is a loud failure rather than a guess
    at what it meant. *)
let is_allow_extra_fields (attr : Parsetree.attribute) =
  match attr.Parsetree.attr_name.txt with
  | "yojson.allow_extra_fields" -> (
      match attr.Parsetree.attr_payload with
      | Parsetree.PStr [] -> true
      | _ -> failf "[@@yojson.allow_extra_fields] takes no payload")
  | _ -> false

let allows_extra_fields (decl : Parsetree.type_declaration) : bool =
  List.exists is_allow_extra_fields decl.Parsetree.ptype_attributes

(* ---------- Type shapes ---------- *)

type env = { source : string; group : string list }
(** [source] is the file text (for [@default] slices); [group] names the types derived in
    the current [type ... and ...] group, whose converters may call each other. *)

type field_info = {
  fname : string;
  key : string;
  fty : Parsetree.core_type;
  default : string option;
  encode_null : bool;
}

let rec is_option_type (ty : Parsetree.core_type) : bool =
  match ty.Parsetree.ptyp_desc with
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident "option"; _ }, [ _ ]) -> true
  | Parsetree.Ptyp_alias (inner, _, _) -> is_option_type inner
  | _ -> false

let field_of_label env (label : Parsetree.label_declaration) : field_info =
  let key = ref label.Parsetree.pld_name.txt in
  let default = ref None in
  let encode_null = ref false in
  List.iter
    (fun attr ->
      match attr.Parsetree.attr_name.txt with
      | "key" -> (
          match string_of_key_payload attr with
          | Some name -> key := name
          | None ->
              failf "field %s: [@key] expects a string literal"
                label.Parsetree.pld_name.txt)
      | "default" -> (
          match expr_of_default_payload ~source:env.source attr with
          | Some expr -> default := Some expr
          | None ->
              failf "field %s: [@default] expects one expression"
                label.Parsetree.pld_name.txt)
      | "yojson.null" -> (
          match attr.Parsetree.attr_payload with
          | Parsetree.PStr [] when is_option_type label.Parsetree.pld_type ->
              encode_null := true
          | Parsetree.PStr [] ->
              failf "field %s: [@yojson.null] requires an option type"
                label.Parsetree.pld_name.txt
          | _ ->
              failf "field %s: [@yojson.null] takes no payload"
                label.Parsetree.pld_name.txt)
      | _ -> ())
    label.Parsetree.pld_attributes;
  {
    fname = label.Parsetree.pld_name.txt;
    key = !key;
    fty = label.Parsetree.pld_type;
    default = !default;
    encode_null = !encode_null;
  }

let cores_of_tuple (pairs : (string option * Parsetree.core_type) list) :
    Parsetree.core_type list =
  List.map
    (fun (label, ty) ->
      match label with
      | None -> ty
      | Some name ->
          failf "labeled tuple element %s is not supported by [@@deriving yojson]" name)
    pairs

(** [longident_path lid] is [Some "A.B.t"] for a [Lident]/[Ldot] chain and [None] for
    anything else. *)
let rec longident_path (lid : Longident.t) : string option =
  match lid with
  | Longident.Lident name -> Some name
  | Longident.Ldot (prefix, name) ->
      Option.map
        (fun path -> path ^ "." ^ name.Location.txt)
        (longident_path prefix.Location.txt)
  | Longident.Lapply _ -> None

(** [qualified_name lid] is [Some (module_path, type_name)] when [lid] names a type in
    another module — ["Other.t"] is [("Other", "t")], ["A.B.t"] is [("A.B", "t")] — and
    [None] for a bare name. The generated code calls that module's public converters
    ([Other.yojson_of_t]/[Other.t_of_yojson]), so a qualified reference needs no [open].
*)
let qualified_name (lid : Longident.t) : (string * string) option =
  match longident_path lid with
  | None -> None
  | Some path -> (
      match String.rindex_opt path '.' with
      | None -> None
      | Some dot ->
          Some
            ( String.sub path 0 dot,
              String.sub path (dot + 1) (String.length path - dot - 1) ))

(* ---------- Converter generation ---------- *)

(** [encode env ty v] is an expression string computing the [Yojson.Safe.t] for the value
    expression [v] of type [ty]. *)
let rec encode env (ty : Parsetree.core_type) (v : string) : string =
  match ty.Parsetree.ptyp_desc with
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident name; _ }, []) -> (
      match name with
      | "string" -> Printf.sprintf "(`String %s)" v
      | "int" -> Printf.sprintf "(`Int %s)" v
      | "bool" -> Printf.sprintf "(`Bool %s)" v
      | "float" -> Printf.sprintf "(`Float %s)" v
      | "unit" -> "`Null"
      | "char" -> Printf.sprintf "(`String (Stdlib.String.make 1 %s))" v
      | _ -> Printf.sprintf "(yojson_of_%s %s)" name v)
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident name; _ }, [ arg ]) -> (
      match name with
      | "option" ->
          Printf.sprintf "(match %s with None -> `Null | Some _ppx_yojson_x -> %s)" v
            (encode env arg "_ppx_yojson_x")
      | "list" ->
          Printf.sprintf "(`List (Stdlib.List.map (fun _ppx_yojson_x -> %s) %s))"
            (encode env arg "_ppx_yojson_x")
            v
      | "array" ->
          Printf.sprintf
            "(`List (Stdlib.Array.to_list (Stdlib.Array.map (fun _ppx_yojson_x -> %s) \
             %s)))"
            (encode env arg "_ppx_yojson_x")
            v
      | _ -> failf "type application %s is not supported by [@@deriving yojson]" name)
  | Parsetree.Ptyp_constr ({ txt = lid; _ }, []) -> (
      match longident_path lid with
      | Some "Yojson.Safe.t" -> v
      | _ -> (
          match qualified_name lid with
          | Some (module_path, name) ->
              Printf.sprintf "(%s.yojson_of_%s %s)" module_path name v
          | None -> failf "this type is not supported by [@@deriving yojson]"))
  | Parsetree.Ptyp_tuple pairs ->
      let tys = cores_of_tuple pairs in
      let binders = List.mapi (fun i _ -> Printf.sprintf "_ppx_yojson_x%d" i) tys in
      let parts = List.mapi (fun i ty -> encode env ty (List.nth binders i)) tys in
      Printf.sprintf "(let (%s) = %s in `List [%s])" (String.concat ", " binders) v
        (String.concat "; " parts)
  | Parsetree.Ptyp_alias (inner, _, _) -> encode env inner v
  | _ -> failf "this type is not supported by [@@deriving yojson]"

let error_at ~path expected j =
  Printf.sprintf "(ppx_yojson_minimal__error %s %S %s)" path expected j

(** [decode env ty ~path j] is an expression string of type [(t, string) result] decoding
    the JSON expression [j], where [path] is an expression string evaluating to the dotted
    path of the value being decoded. *)
let rec decode env (ty : Parsetree.core_type) ~path j : string =
  match ty.Parsetree.ptyp_desc with
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident name; _ }, []) -> (
      match name with
      | "string" ->
          Printf.sprintf
            "(match %s with `String _ppx_yojson_s -> Ok _ppx_yojson_s | _ -> Error %s)" j
            (error_at ~path "string" j)
      | "int" ->
          Printf.sprintf
            "(match %s with `Int _ppx_yojson_i -> Ok _ppx_yojson_i | `Intlit \
             _ppx_yojson_s -> (match Stdlib.int_of_string_opt _ppx_yojson_s with Some \
             _ppx_yojson_i -> Ok _ppx_yojson_i | None -> Error %s) | _ -> Error %s)"
            j (error_at ~path "int" j) (error_at ~path "int" j)
      | "bool" ->
          Printf.sprintf
            "(match %s with `Bool _ppx_yojson_b -> Ok _ppx_yojson_b | _ -> Error %s)" j
            (error_at ~path "bool" j)
      | "float" ->
          Printf.sprintf
            "(match %s with `Float _ppx_yojson_f -> Ok _ppx_yojson_f | `Int \
             _ppx_yojson_i -> Ok (Stdlib.float_of_int _ppx_yojson_i) | _ -> Error %s)"
            j (error_at ~path "number" j)
      | "unit" ->
          Printf.sprintf "(match %s with `Null -> Ok () | _ -> Error %s)" j
            (error_at ~path "null" j)
      | "char" ->
          Printf.sprintf
            "(match %s with `String _ppx_yojson_s when Stdlib.String.length \
             _ppx_yojson_s = 1 -> Ok (Stdlib.String.get _ppx_yojson_s 0) | _ -> Error \
             %s)"
            j
            (error_at ~path "single-character string" j)
      | _ ->
          if List.mem name env.group then
            Printf.sprintf "(ppx_yojson_decode_%s %s %s)" name path j
          else
            Printf.sprintf
              "(match %s_of_yojson %s with Ok _ as _ppx_yojson_ok -> _ppx_yojson_ok | \
               Error _ppx_yojson_e -> Error (%s ^ \": \" ^ _ppx_yojson_e))"
              name j path)
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident name; _ }, [ arg ]) -> (
      match name with
      | "option" ->
          Printf.sprintf
            "(match %s with `Null -> Ok None | _ -> (match %s with Ok _ppx_yojson_x -> \
             Ok (Some _ppx_yojson_x) | Error _ppx_yojson_e -> Error _ppx_yojson_e))"
            j (decode env arg ~path j)
      | "list" -> decode_list env arg ~path j
      | "array" ->
          Printf.sprintf
            "(match %s with Ok _ppx_yojson_items -> Ok (Stdlib.Array.of_list \
             _ppx_yojson_items) | Error _ppx_yojson_e -> Error _ppx_yojson_e)"
            (decode_list env arg ~path j)
      | _ -> failf "type application %s is not supported by [@@deriving yojson]" name)
  | Parsetree.Ptyp_constr ({ txt = lid; _ }, []) -> (
      match longident_path lid with
      | Some "Yojson.Safe.t" -> Printf.sprintf "(Ok %s)" j
      | _ -> (
          match qualified_name lid with
          | Some (module_path, name) ->
              Printf.sprintf
                "(match %s.%s_of_yojson %s with Ok _ as _ppx_yojson_ok -> _ppx_yojson_ok \
                 | Error _ppx_yojson_e -> Error (%s ^ \": \" ^ _ppx_yojson_e))"
                module_path name j path
          | None -> failf "this type is not supported by [@@deriving yojson]"))
  | Parsetree.Ptyp_tuple pairs -> decode_tuple env (cores_of_tuple pairs) ~path j
  | Parsetree.Ptyp_alias (inner, _, _) -> decode env inner ~path j
  | _ -> failf "this type is not supported by [@@deriving yojson]"

and decode_list env elem ~path j =
  let item_path =
    Printf.sprintf "(%s ^ \".[\" ^ Stdlib.string_of_int _ppx_yojson_i ^ \"]\")" path
  in
  Printf.sprintf
    "(match %s with `List _ppx_yojson_items -> let rec _ppx_yojson_loop _ppx_yojson_i \
     _ppx_yojson_acc = function [] -> Ok (Stdlib.List.rev _ppx_yojson_acc) | \
     _ppx_yojson_j :: _ppx_yojson_rest -> (match %s with Ok _ppx_yojson_x -> \
     _ppx_yojson_loop (_ppx_yojson_i + 1) (_ppx_yojson_x :: _ppx_yojson_acc) \
     _ppx_yojson_rest | Error _ppx_yojson_e -> Error _ppx_yojson_e) in _ppx_yojson_loop \
     0 [] _ppx_yojson_items | _ -> Error %s)"
    j
    (decode env elem ~path:item_path "_ppx_yojson_j")
    (error_at ~path "array" j)

and decode_tuple env tys ~path j =
  let n = List.length tys in
  let binders = List.init n (fun i -> Printf.sprintf "_ppx_yojson_j%d" i) in
  let rec chain i =
    if i = n then
      Printf.sprintf "(Ok (%s))"
        (String.concat ", " (List.init n (fun k -> Printf.sprintf "_ppx_yojson_x%d" k)))
    else
      let sub = Printf.sprintf "(%s ^ %S)" path ("." ^ string_of_int i) in
      Printf.sprintf
        "(match %s with Ok _ppx_yojson_x%d -> %s | Error _ppx_yojson_e -> Error \
         _ppx_yojson_e)"
        (decode env (List.nth tys i) ~path:sub (List.nth binders i))
        i
        (chain (i + 1))
  in
  Printf.sprintf "(match %s with `List [%s] -> %s | _ -> Error %s)" j
    (String.concat "; " binders) (chain 0)
    (error_at ~path (Printf.sprintf "array of %d" n) j)
(* ---------- Records and variants ---------- *)

let decode_record_field env parent_path (field : field_info) rest =
  let sub = Printf.sprintf "(%s ^ %S)" parent_path ("." ^ field.key) in
  let missing =
    match field.default with
    | Some expr ->
        Printf.sprintf "(let _ppx_yojson_v_%s = (%s) in %s)" field.fname expr rest
    | None when is_option_type field.fty ->
        Printf.sprintf "(let _ppx_yojson_v_%s = None in %s)" field.fname rest
    | None ->
        Printf.sprintf "(Error (%s ^ \": missing field \" ^ %S))" parent_path field.key
  in
  Printf.sprintf
    "(match Stdlib.List.assoc_opt %S _ppx_yojson_fields with None -> %s | Some \
     _ppx_yojson_j -> (match %s with Ok _ppx_yojson_v_%s -> %s | Error _ppx_yojson_e -> \
     Error _ppx_yojson_e))"
    field.key missing
    (decode env field.fty ~path:sub "_ppx_yojson_j")
    field.fname rest

let encode_record env fields v =
  let parts =
    List.map
      (fun field ->
        let value = v ^ "." ^ field.fname in
        let pair = Printf.sprintf "(%S, %s)" field.key (encode env field.fty value) in
        if is_option_type field.fty && not field.encode_null then
          Printf.sprintf "(match %s with None -> [] | Some _ -> [%s])" value pair
        else Printf.sprintf "[%s]" pair)
      fields
  in
  Printf.sprintf "(`Assoc (Stdlib.List.concat [%s]))" (String.concat "; " parts)

(** [reject_unknown_fields fields record] wraps the [Ok { ... }] expression [record] in a
    check that the decoded object names no field the type does not: the first unknown key
    is reported with the record's dotted path, which is what a config or request decode
    must do (an unknown key is a typo, not forward compatibility). A type carrying
    [[@@yojson.allow_extra_fields]] skips the check and ignores what it does not know. *)
let reject_unknown_fields fields record =
  let known =
    String.concat "; " (List.map (fun field -> Printf.sprintf "%S" field.key) fields)
  in
  Printf.sprintf
    "(match Stdlib.List.filter_map (fun (_ppx_yojson_key, _) -> if Stdlib.List.mem      \
     _ppx_yojson_key [%s] then None else Some _ppx_yojson_key) _ppx_yojson_fields with \
     []      -> %s | _ppx_yojson_key :: _ -> Error (_ppx_yojson_path ^ \": unknown field \
     \" ^      _ppx_yojson_key))"
    known record

let decode_record env ~allow_extra_fields fields =
  let rec chain parent_path = function
    | [] ->
        let parts =
          List.map
            (fun field -> Printf.sprintf "%s = _ppx_yojson_v_%s" field.fname field.fname)
            fields
        in
        let record = Printf.sprintf "(Ok { %s })" (String.concat "; " parts) in
        if allow_extra_fields then record else reject_unknown_fields fields record
    | field :: rest -> decode_record_field env parent_path field (chain parent_path rest)
  in
  Printf.sprintf
    "(match _ppx_yojson_json with `Assoc _ppx_yojson_fields -> %s | _ -> Error %s)"
    (chain "_ppx_yojson_path" fields)
    (error_at ~path:"_ppx_yojson_path" "object" "_ppx_yojson_json")

let wire_name type_name (ctor : Parsetree.constructor_declaration) =
  let names =
    List.filter
      (fun attr -> attr.Parsetree.attr_name.txt = "name")
      ctor.Parsetree.pcd_attributes
  in
  match names with
  | [] -> ctor.Parsetree.pcd_name.txt
  | [ attr ] -> (
      match string_of_key_payload attr with
      | Some name -> name
      | None ->
          failf "type %s constructor %s: [@name] expects a string literal" type_name
            ctor.Parsetree.pcd_name.txt)
  | _ ->
      failf "type %s constructor %s: duplicate [@name]" type_name
        ctor.Parsetree.pcd_name.txt

let encode_constructor env type_name (ctor : Parsetree.constructor_declaration) =
  let tag = ctor.Parsetree.pcd_name.txt in
  let wire = wire_name type_name ctor in
  match ctor.Parsetree.pcd_args with
  | Parsetree.Pcstr_tuple [] -> Printf.sprintf "%s -> `String %S" tag wire
  | Parsetree.Pcstr_tuple [ arg ] ->
      Printf.sprintf "%s _ppx_yojson_x -> `List [`String %S; %s]" tag wire
        (encode env arg.Parsetree.pca_type "_ppx_yojson_x")
  | Parsetree.Pcstr_tuple args ->
      let tys = List.map (fun a -> a.Parsetree.pca_type) args in
      let binders = List.mapi (fun i _ -> Printf.sprintf "_ppx_yojson_x%d" i) tys in
      let parts = List.mapi (fun i ty -> encode env ty (List.nth binders i)) tys in
      Printf.sprintf "%s (%s) -> `List [`String %S; %s]" tag (String.concat ", " binders)
        wire (String.concat "; " parts)
  | Parsetree.Pcstr_record _ ->
      failf "type %s: inline record constructors are not supported" type_name

let decode_constructor env type_name path (ctor : Parsetree.constructor_declaration) =
  let tag = ctor.Parsetree.pcd_name.txt in
  let wire = wire_name type_name ctor in
  let sub = Printf.sprintf "(%s ^ %S)" path ("." ^ wire) in
  match ctor.Parsetree.pcd_args with
  | Parsetree.Pcstr_tuple [] -> Printf.sprintf "| `String %S -> Ok %s" wire tag
  | Parsetree.Pcstr_tuple [ arg ] ->
      Printf.sprintf
        "| `List [`String %S; _ppx_yojson_j] -> (match %s with Ok _ppx_yojson_x -> Ok \
         (%s _ppx_yojson_x) | Error _ppx_yojson_e -> Error _ppx_yojson_e)"
        wire
        (decode env arg.Parsetree.pca_type ~path:sub "_ppx_yojson_j")
        tag
  | Parsetree.Pcstr_tuple args ->
      let tys = List.map (fun a -> a.Parsetree.pca_type) args in
      let binders = List.mapi (fun i _ -> Printf.sprintf "_ppx_yojson_j%d" i) tys in
      let rec chain i =
        if i = List.length tys then
          Printf.sprintf "(Ok (%s (%s)))" tag
            (String.concat ", "
               (List.mapi (fun k _ -> Printf.sprintf "_ppx_yojson_x%d" k) tys))
        else
          Printf.sprintf
            "(match %s with Ok _ppx_yojson_x%d -> %s | Error _ppx_yojson_e -> Error \
             _ppx_yojson_e)"
            (decode env (List.nth tys i) ~path:sub (List.nth binders i))
            i
            (chain (i + 1))
      in
      Printf.sprintf "| `List [`String %S; %s] -> %s" wire (String.concat "; " binders)
        (chain 0)
  | Parsetree.Pcstr_record _ ->
      failf "type %s: inline record constructors are not supported" type_name

let check_constructor type_name (ctor : Parsetree.constructor_declaration) =
  (match ctor.Parsetree.pcd_vars with
  | [] -> ()
  | _ -> failf "type %s: existential constructors are not supported" type_name);
  match ctor.Parsetree.pcd_res with
  | None -> ()
  | Some _ -> failf "type %s: GADT constructors are not supported" type_name

(* ---------- Declarations and groups ---------- *)

let check_decl (decl : Parsetree.type_declaration) : string =
  let name = decl.Parsetree.ptype_name.txt in
  (match decl.Parsetree.ptype_params with
  | [] -> ()
  | _ -> failf "type %s: type parameters are not supported" name);
  (match decl.Parsetree.ptype_cstrs with
  | [] -> ()
  | _ -> failf "type %s: constrained types are not supported" name);
  (match decl.Parsetree.ptype_private with
  | Asttypes.Private -> failf "type %s: private types are not supported" name
  | Asttypes.Public -> ());
  name

(** An explicit marker is needed because OxCaml cannot parse an empty record type. *)
let is_empty_record (decl : Parsetree.type_declaration) =
  let attrs =
    List.filter
      (fun attr -> attr.Parsetree.attr_name.txt = "yojson.empty_record")
      decl.Parsetree.ptype_attributes
  in
  match attrs with
  | [] -> false
  | [ attr ] -> (
      match
        ( attr.Parsetree.attr_payload,
          decl.Parsetree.ptype_kind,
          decl.Parsetree.ptype_manifest )
      with
      | ( Parsetree.PStr [],
          Parsetree.Ptype_abstract,
          Some
            {
              Parsetree.ptyp_desc =
                Parsetree.Ptyp_constr ({ txt = Longident.Lident "unit"; _ }, []);
              _;
            } ) ->
          true
      | _ ->
          failf "type %s: [@@yojson.empty_record] requires a unit alias and no payload"
            decl.Parsetree.ptype_name.txt)
  | _ -> failf "type %s: duplicate [@@yojson.empty_record]" decl.Parsetree.ptype_name.txt

(** One declaration contributes its encoder and private path-threading decoder to the
    group chain, plus a standalone public wrapper [let] afterwards: simultaneous
    non-recursive bindings cannot see each other, so the wrapper (which calls the private
    decoder) must follow the chain. *)
let gen_structure_decl env (decl : Parsetree.type_declaration) : string list * string =
  let name = check_decl decl in
  let empty_record = is_empty_record decl in
  if empty_record && allows_extra_fields decl then
    failf "type %s: [@@yojson.empty_record] cannot allow extra fields" name;
  let encoded, decoded =
    if empty_record then
      ( "(`Assoc [])",
        Printf.sprintf
          "(match _ppx_yojson_json with `Assoc _ppx_yojson_fields -> %s | _ -> Error %s)"
          (reject_unknown_fields [] "(Ok ())")
          (error_at ~path:"_ppx_yojson_path" "object" "_ppx_yojson_json") )
    else
      match decl.Parsetree.ptype_kind with
      | Parsetree.Ptype_record labels ->
          let fields = List.map (field_of_label env) labels in
          ( encode_record env fields "_ppx_yojson_v",
            decode_record env ~allow_extra_fields:(allows_extra_fields decl) fields )
      | Parsetree.Ptype_variant ctors ->
          (match ctors with
          | [] -> failf "type %s: empty variants are not supported" name
          | _ -> ());
          List.iter (check_constructor name) ctors;
          let names = List.map (wire_name name) ctors in
          let seen = Hashtbl.create (List.length names) in
          List.iter
            (fun wire ->
              if Hashtbl.mem seen wire then
                failf "type %s: duplicate variant wire name %S" name wire;
              Hashtbl.add seen wire ())
            names;
          let tags = String.concat " | " (List.map (Printf.sprintf "%S") names) in
          let enc_cases =
            String.concat " | " (List.map (encode_constructor env name) ctors)
          in
          let dec_cases =
            String.concat " "
              (List.map (decode_constructor env name "_ppx_yojson_path") ctors)
          in
          ( Printf.sprintf "(match _ppx_yojson_v with %s)" enc_cases,
            Printf.sprintf "(match _ppx_yojson_json with %s | _ -> Error %s)" dec_cases
              (error_at ~path:"_ppx_yojson_path" tags "_ppx_yojson_json") )
      | Parsetree.Ptype_abstract -> (
          match decl.Parsetree.ptype_manifest with
          | Some core ->
              ( encode env core "_ppx_yojson_v",
                decode env core ~path:"_ppx_yojson_path" "_ppx_yojson_json" )
          | None -> failf "type %s: abstract types cannot derive yojson" name)
      | Parsetree.Ptype_open ->
          failf "type %s: extensible variant types are not supported" name
      | Parsetree.Ptype_record_unboxed_product _ ->
          failf "type %s: unboxed record products are not supported" name
  in
  ( [
      Printf.sprintf "yojson_of_%s (_ppx_yojson_v : %s) : Yojson.Safe.t = %s" name name
        encoded;
      Printf.sprintf
        "ppx_yojson_decode_%s (_ppx_yojson_path : string) (_ppx_yojson_json : \
         Yojson.Safe.t) : (%s, string) result = %s"
        name name decoded;
    ],
    Printf.sprintf
      "let %s_of_yojson (_ppx_yojson_json : Yojson.Safe.t) : (%s, string) result = \
       ppx_yojson_decode_%s %S _ppx_yojson_json"
      name name name name )

let gen_signature_decl (decl : Parsetree.type_declaration) : string list =
  let name = check_decl decl in
  ignore (is_empty_record decl);
  (match decl.Parsetree.ptype_kind with
  | Parsetree.Ptype_abstract when decl.Parsetree.ptype_manifest = None ->
      failf "type %s: abstract types cannot derive yojson" name
  | _ -> ());
  [
    Printf.sprintf "val yojson_of_%s : %s -> Yojson.Safe.t" name name;
    Printf.sprintf "val %s_of_yojson : Yojson.Safe.t -> (%s, string) result" name name;
  ]

let prelude =
  "let ppx_yojson_minimal__truncate (_ppx_yojson_json : Yojson.Safe.t) : string =\n"
  ^ "  let _ppx_yojson_text = Yojson.Safe.to_string _ppx_yojson_json in\n"
  ^ "  if Stdlib.String.length _ppx_yojson_text > 200 then Stdlib.String.sub \
     _ppx_yojson_text 0 200 ^ \"...\" else _ppx_yojson_text\n" ^ "\n"
  ^ "let ppx_yojson_minimal__error (_ppx_yojson_path : string) (_ppx_yojson_expected : \
     string) (_ppx_yojson_json : Yojson.Safe.t) : string =\n"
  ^ "  _ppx_yojson_path ^ \": expected \" ^ _ppx_yojson_expected ^ \", got \" ^ \
     ppx_yojson_minimal__truncate _ppx_yojson_json\n"

(* ---------- Collecting work ---------- *)

type group = {
  decls : Parsetree.type_declaration list;
  line : int;
  blanks : (int * int) list;
  insert_at : int;
  insert_line : int;
}

(** The attributes on one declaration that the compiler must not see again: blank spans
    for [yojson] and for [[@@yojson.allow_extra_fields]], loud failures for anything else
    a top-level type should not carry. *)
let blanks_of_decl ~source (decl : Parsetree.type_declaration) : (int * int) list =
  List.filter_map
    (fun attr ->
      if is_deriving attr then
        match classify_deriving_payload attr.Parsetree.attr_payload with
        | Yojson -> Some (attribute_span ~source attr)
        | Other name ->
            failf "[@@deriving %s] is not supported: only [@@deriving yojson] is" name
        | Complex ->
            failf "unsupported [@@deriving] payload: write one deriver per attribute"
      else if
        is_allow_extra_fields attr || attr.Parsetree.attr_name.txt = "yojson.empty_record"
      then Some (attribute_span ~source attr)
      else None)
    decl.Parsetree.ptype_attributes

(** Any [@@deriving yojson] below the top level is a loud failure: the generator only
    appends top-level converters, so anything else would silently do nothing. Other
    derivers below the top level are left alone. *)
let check_nested_decls context (decls : Parsetree.type_declaration list) =
  List.iter
    (fun decl ->
      List.iter
        (fun attr ->
          if is_deriving attr then
            match classify_deriving_payload attr.Parsetree.attr_payload with
            | Yojson ->
                failf "%s: [@@deriving yojson] below the top level is not supported"
                  context
            | Other _ | Complex -> ())
        decl.Parsetree.ptype_attributes)
    decls

(** A top-level [@@deriving yojson] anywhere but on a type declaration is a loud failure
    for the same reason. *)
let check_top_attributes context (attrs : Parsetree.attributes) =
  List.iter
    (fun attr ->
      if is_deriving attr then
        match classify_deriving_payload attr.Parsetree.attr_payload with
        | Yojson ->
            failf "%s: [@@deriving yojson] is only supported on type declarations" context
        | Other _ | Complex -> ())
    attrs

let rec scan_module_expr expr =
  match expr.Parsetree.pmod_desc with
  | Parsetree.Pmod_structure items -> List.iter scan_structure_item items
  | Parsetree.Pmod_functor (_, body) -> scan_module_expr body
  | Parsetree.Pmod_apply (f, x) ->
      scan_module_expr f;
      scan_module_expr x
  | Parsetree.Pmod_apply_unit m -> scan_module_expr m
  | Parsetree.Pmod_constraint (m, ty, _) -> (
      scan_module_expr m;
      match ty with Some t -> scan_module_type t | None -> ())
  | Parsetree.Pmod_unpack _ | Parsetree.Pmod_extension _ | Parsetree.Pmod_ident _
  | Parsetree.Pmod_instance _ ->
      ()

and scan_module_type mty =
  match mty.Parsetree.pmty_desc with
  | Parsetree.Pmty_signature items ->
      List.iter scan_signature_item items.Parsetree.psg_items
  | Parsetree.Pmty_functor (_, body, _) -> scan_module_type body
  | Parsetree.Pmty_with (t, _) -> scan_module_type t
  | Parsetree.Pmty_typeof m -> scan_module_expr m
  | Parsetree.Pmty_extension _ | Parsetree.Pmty_ident _ | Parsetree.Pmty_alias _
  | Parsetree.Pmty_strengthen _ ->
      ()

and scan_structure_item (item : Parsetree.structure_item) =
  match item.Parsetree.pstr_desc with
  | Parsetree.Pstr_type (_, decls) -> check_nested_decls "a module" decls
  | Parsetree.Pstr_module binding ->
      check_top_attributes "a module" binding.Parsetree.pmb_attributes;
      scan_module_expr binding.Parsetree.pmb_expr
  | Parsetree.Pstr_recmodule bindings ->
      List.iter
        (fun b ->
          check_top_attributes "a module" b.Parsetree.pmb_attributes;
          scan_module_expr b.Parsetree.pmb_expr)
        bindings
  | Parsetree.Pstr_include incl -> scan_module_expr incl.Parsetree.pincl_mod
  | Parsetree.Pstr_value (_, bindings) ->
      List.iter
        (fun b -> check_top_attributes "a value" b.Parsetree.pvb_attributes)
        bindings
  | Parsetree.Pstr_primitive desc ->
      check_top_attributes "an external" desc.Parsetree.pval_attributes
  | Parsetree.Pstr_exception exn ->
      check_top_attributes "an exception" exn.Parsetree.ptyexn_attributes
  | Parsetree.Pstr_open desc ->
      check_top_attributes "an open" desc.Parsetree.popen_attributes
  | _ -> ()

and scan_signature_item (item : Parsetree.signature_item) =
  match item.Parsetree.psig_desc with
  | Parsetree.Psig_type (_, decls) -> check_nested_decls "a module type" decls
  | Parsetree.Psig_typesubst decls -> check_nested_decls "a module type" decls
  | Parsetree.Psig_module md -> scan_module_type md.Parsetree.pmd_type
  | Parsetree.Psig_recmodule mds ->
      List.iter (fun md -> scan_module_type md.Parsetree.pmd_type) mds
  | Parsetree.Psig_include (incl, _) -> scan_module_type incl.Parsetree.pincl_mod
  | Parsetree.Psig_modtype mtd -> (
      match mtd.Parsetree.pmtd_type with Some ty -> scan_module_type ty | None -> ())
  | Parsetree.Psig_value desc ->
      check_top_attributes "a value" desc.Parsetree.pval_attributes
  | Parsetree.Psig_exception exn ->
      check_top_attributes "an exception" exn.Parsetree.ptyexn_attributes
  | Parsetree.Psig_open desc ->
      check_top_attributes "an open" desc.Parsetree.popen_attributes
  | _ -> ()

(* ---------- Top-level collection ---------- *)

let line_of_decl (decl : Parsetree.type_declaration) =
  decl.Parsetree.ptype_loc.Location.loc_start.pos_lnum

let line_at_offset source offset =
  let line = ref 1 in
  for i = 0 to offset - 1 do
    if source.[i] = Char.chr 10 then incr line
  done;
  !line

(** Top-level [type ... and ...]: a group job when any declaration carries a [@@deriving]
    attribute, in which case every declaration is derived. The converters are inserted
    right after the declaration (OCaml needs definition before use); a [#]-line directive
    after the insert restores the original numbering for everything that follows. A group
    with no [@@deriving] is left alone, even when it carries
    [[@@yojson.allow_extra_fields]]: there is nothing to derive and so nothing to allow.
*)
let group_of_decls ~source ~insert_at (decls : Parsetree.type_declaration list) :
    group option =
  let derives =
    List.exists
      (fun decl -> List.exists is_deriving decl.Parsetree.ptype_attributes)
      decls
  in
  if not derives then None
  else
    let blanks = List.concat_map (blanks_of_decl ~source) decls in
    match blanks with
    | [] -> None
    | _ ->
        let line = line_of_decl (List.hd decls) in
        let insert_line = line_at_offset source insert_at in
        Some { decls; line; blanks; insert_at; insert_line }

let collect_structure ~source (items : Parsetree.structure) : group list =
  List.filter_map
    (fun item ->
      match item.Parsetree.pstr_desc with
      | Parsetree.Pstr_type (_, decls) ->
          group_of_decls ~source
            ~insert_at:item.Parsetree.pstr_loc.Location.loc_end.pos_cnum decls
      | Parsetree.Pstr_value (_, bindings) ->
          List.iter
            (fun b -> check_top_attributes "a value" b.Parsetree.pvb_attributes)
            bindings;
          None
      | Parsetree.Pstr_primitive desc ->
          check_top_attributes "an external" desc.Parsetree.pval_attributes;
          None
      | Parsetree.Pstr_exception exn ->
          check_top_attributes "an exception" exn.Parsetree.ptyexn_attributes;
          None
      | Parsetree.Pstr_module binding ->
          check_top_attributes "a module" binding.Parsetree.pmb_attributes;
          scan_module_expr binding.Parsetree.pmb_expr;
          None
      | Parsetree.Pstr_recmodule bindings ->
          List.iter
            (fun b ->
              check_top_attributes "a module" b.Parsetree.pmb_attributes;
              scan_module_expr b.Parsetree.pmb_expr)
            bindings;
          None
      | Parsetree.Pstr_include incl ->
          scan_module_expr incl.Parsetree.pincl_mod;
          None
      | Parsetree.Pstr_modtype mtd ->
          check_top_attributes "a module type" mtd.Parsetree.pmtd_attributes;
          (match mtd.Parsetree.pmtd_type with
          | Some ty -> scan_module_type ty
          | None -> ());
          None
      | Parsetree.Pstr_open desc ->
          check_top_attributes "an open" desc.Parsetree.popen_attributes;
          None
      | Parsetree.Pstr_class cls ->
          List.iter
            (fun c -> check_top_attributes "a class" c.Parsetree.pci_attributes)
            cls;
          None
      | Parsetree.Pstr_typext ext ->
          check_top_attributes "a type extension" ext.Parsetree.ptyext_attributes;
          None
      | Parsetree.Pstr_eval _ | Parsetree.Pstr_class_type _ | Parsetree.Pstr_attribute _
      | Parsetree.Pstr_extension _ | Parsetree.Pstr_jkind _ ->
          None)
    items

let collect_signature ~source (signature : Parsetree.signature) : group list =
  List.filter_map
    (fun item ->
      match item.Parsetree.psig_desc with
      | Parsetree.Psig_type (_, decls) ->
          group_of_decls ~source
            ~insert_at:item.Parsetree.psig_loc.Location.loc_end.pos_cnum decls
      | Parsetree.Psig_typesubst decls ->
          check_nested_decls "a type substitution" decls;
          None
      | Parsetree.Psig_value desc ->
          check_top_attributes "a value" desc.Parsetree.pval_attributes;
          None
      | Parsetree.Psig_typext ext ->
          check_top_attributes "a type extension" ext.Parsetree.ptyext_attributes;
          None
      | Parsetree.Psig_exception exn ->
          check_top_attributes "an exception" exn.Parsetree.ptyexn_attributes;
          None
      | Parsetree.Psig_open desc ->
          check_top_attributes "an open" desc.Parsetree.popen_attributes;
          None
      | Parsetree.Psig_include (incl, _) ->
          scan_module_type incl.Parsetree.pincl_mod;
          None
      | Parsetree.Psig_module md ->
          check_top_attributes "a module" md.Parsetree.pmd_attributes;
          scan_module_type md.Parsetree.pmd_type;
          None
      | Parsetree.Psig_recmodule mds ->
          List.iter
            (fun md ->
              check_top_attributes "a module" md.Parsetree.pmd_attributes;
              scan_module_type md.Parsetree.pmd_type)
            mds;
          None
      | Parsetree.Psig_modtype mtd ->
          check_top_attributes "a module type" mtd.Parsetree.pmtd_attributes;
          (match mtd.Parsetree.pmtd_type with
          | Some ty -> scan_module_type ty
          | None -> ());
          None
      | Parsetree.Psig_class cls ->
          List.iter
            (fun c -> check_top_attributes "a class" c.Parsetree.pci_attributes)
            cls;
          None
      | Parsetree.Psig_class_type cls ->
          List.iter
            (fun c -> check_top_attributes "a class type" c.Parsetree.pci_attributes)
            cls;
          None
      | Parsetree.Psig_modsubst _ | Parsetree.Psig_modtypesubst _ | Parsetree.Psig_jkind _
      | Parsetree.Psig_attribute _ | Parsetree.Psig_extension _ ->
          None)
    signature.Parsetree.psg_items

(* ---------- Assembly and entry point ---------- *)

(** Splice the generated converters into the source right after the type declaration that
    requested them, blanking the attribute spans. A [#]-line directive after each insert
    restores the original numbering, so errors in the surrounding code still point at the
    right lines. *)
let assemble ~source ~filename ~prelude blanks groups codes =
  let bytes = Bytes.of_string source in
  List.iter
    (fun (start, stop) -> Bytes.fill bytes start (stop - start) (Char.chr 32))
    blanks;
  let base = Bytes.to_string bytes in
  let out = Buffer.create (String.length source + 4096) in
  let pos = ref 0 in
  let first = ref true in
  List.iter
    (fun (group, code) ->
      Buffer.add_substring out base !pos (group.insert_at - !pos);
      pos := group.insert_at;
      Buffer.add_char out (Char.chr 10);
      if !first then (
        first := false;
        Buffer.add_string out "(* Generated by ppx-yojson-minimal. Do not edit. *)";
        Buffer.add_char out (Char.chr 10);
        Buffer.add_string out "[@@@warning ";
        Buffer.add_char out (Char.chr 34);
        Buffer.add_string out "-32";
        Buffer.add_char out (Char.chr 34);
        Buffer.add_string out "]";
        Buffer.add_char out (Char.chr 10);
        (match prelude with None -> () | Some text -> Buffer.add_string out text);
        Buffer.add_char out (Char.chr 10));
      Buffer.add_string out
        (Printf.sprintf "# %d %S" group.line (escape_filename filename));
      Buffer.add_char out (Char.chr 10);
      Buffer.add_string out code;
      Buffer.add_char out (Char.chr 10);
      Buffer.add_string out
        (Printf.sprintf "# %d %S" group.insert_line (escape_filename filename));
      Buffer.add_char out (Char.chr 10))
    (List.combine groups codes);
  Buffer.add_substring out base !pos (String.length base - !pos);
  Buffer.contents out

let lexbuf_of ~filename source =
  let lexbuf = Lexing.from_string source in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  lexbuf

let rec refs_of_core acc (ty : Parsetree.core_type) : string list =
  match ty.Parsetree.ptyp_desc with
  | Parsetree.Ptyp_constr ({ txt = Longident.Lident name; _ }, args) ->
      List.fold_left refs_of_core (name :: acc) args
  | Parsetree.Ptyp_constr (_, args) -> List.fold_left refs_of_core acc args
  | Parsetree.Ptyp_tuple pairs -> List.fold_left refs_of_core acc (List.map snd pairs)
  | Parsetree.Ptyp_alias (inner, _, _) -> refs_of_core acc inner
  | _ -> acc

let refs_of_decl (decl : Parsetree.type_declaration) : string list =
  let of_kind =
    match decl.Parsetree.ptype_kind with
    | Parsetree.Ptype_record labels -> List.map (fun l -> l.Parsetree.pld_type) labels
    | Parsetree.Ptype_variant ctors ->
        List.concat_map
          (fun ctor ->
            match ctor.Parsetree.pcd_args with
            | Parsetree.Pcstr_tuple args -> List.map (fun a -> a.Parsetree.pca_type) args
            | Parsetree.Pcstr_record _ -> [])
          ctors
    | Parsetree.Ptype_abstract -> (
        match decl.Parsetree.ptype_manifest with Some core -> [ core ] | None -> [])
    | Parsetree.Ptype_open -> []
    | Parsetree.Ptype_record_unboxed_product _ -> []
  in
  List.fold_left refs_of_core [] of_kind

(** [let rec] only when the group needs it: several declarations, or a declaration that
    names a type of the group. Anything else is [let], so the generated code raises no
    unused-rec warning of its own. *)
let binding_of_group (names : string list) (decls : Parsetree.type_declaration list) :
    string =
  if List.length decls > 1 then "let rec "
  else if
    List.exists (fun d -> List.exists (fun n -> List.mem n names) (refs_of_decl d)) decls
  then "let rec "
  else "let "

let generate_structure ~source ~filename groups =
  let blanks = List.concat_map (fun g -> g.blanks) groups in
  let codes =
    List.map
      (fun group ->
        let names = List.map (fun d -> d.Parsetree.ptype_name.txt) group.decls in
        let env = { source; group = names } in
        let mains, wraps = List.split (List.map (gen_structure_decl env) group.decls) in
        binding_of_group names group.decls
        ^ String.concat "\nand " (List.concat mains)
        ^ "\n" ^ String.concat "\n" wraps)
      groups
  in
  assemble ~source ~filename ~prelude:(Some prelude) blanks groups codes

let generate_signature ~source ~filename groups =
  let blanks = List.concat_map (fun g -> g.blanks) groups in
  let codes =
    List.map
      (fun group -> String.concat "\n" (List.concat_map gen_signature_decl group.decls))
      groups
  in
  assemble ~source ~filename ~prelude:None blanks groups codes

let process ~filename ~source =
  if not (has_substring "deriving" source) then Ok source
  else
    let is_interface = Filename.check_suffix filename ".mli" in
    let parsed =
      if is_interface then
        match Parse.interface (lexbuf_of ~filename source) with
        | items -> Some (`Signature items)
        | exception (Syntaxerr.Error _ | Lexer.Error _) -> None
      else
        match Parse.implementation (lexbuf_of ~filename source) with
        | items -> Some (`Structure items)
        | exception (Syntaxerr.Error _ | Lexer.Error _) -> None
    in
    match parsed with
    | None -> Ok source
    | Some (`Structure items) -> (
        match
          match collect_structure ~source items with
          | [] -> None
          | groups -> Some (generate_structure ~source ~filename groups)
        with
        | None -> Ok source
        | Some output -> Ok output
        | exception Fail message -> Error (filename ^ ": " ^ message))
    | Some (`Signature items) -> (
        match
          match collect_signature ~source items with
          | [] -> None
          | groups -> Some (generate_signature ~source ~filename groups)
        with
        | None -> Ok source
        | Some output -> Ok output
        | exception Fail message -> Error (filename ^ ": " ^ message))
