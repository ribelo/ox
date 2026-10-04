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

type mode = Bidirectional | Encoder_only
type deriving = Yojson of mode | Other of string | Complex

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
      ] -> (
      match name with
      | "yojson" -> Yojson Bidirectional
      | "yojson_of" -> Yojson Encoder_only
      | _ -> Other name)
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
(** [source] is the file text (for [@json.default] slices); [group] names the types
    derived in the current [type ... and ...] group, whose converters may call each other.
*)

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

(** The names this deriver accepted before ^nderive-ze85 renamed them to jsonkit's. An old
    name left behind would silently change the wire — [zip] instead of [zipCode] — so it
    is refused with the name to write instead, never ignored. *)
let retired_attribute ~context old replacement =
  failf "%s: [@%s] is not the deriver's attribute name any more: write [@%s]" context old
    replacement

let field_of_label env (label : Parsetree.label_declaration) : field_info =
  let context = Printf.sprintf "field %s" label.Parsetree.pld_name.txt in
  let key = ref label.Parsetree.pld_name.txt in
  let default = ref None in
  let encode_null = ref false in
  List.iter
    (fun attr ->
      match attr.Parsetree.attr_name.txt with
      | "json.key" -> (
          match string_of_key_payload attr with
          | Some name -> key := name
          | None -> failf "%s: [@json.key] expects a string literal" context)
      | "json.default" -> (
          match expr_of_default_payload ~source:env.source attr with
          | Some expr -> default := Some expr
          | None -> failf "%s: [@json.default] expects one expression" context)
      | "json.null" -> (
          match attr.Parsetree.attr_payload with
          | Parsetree.PStr [] when is_option_type label.Parsetree.pld_type ->
              encode_null := true
          | Parsetree.PStr [] -> failf "%s: [@json.null] requires an option type" context
          | _ -> failf "%s: [@json.null] takes no payload" context)
      | "key" -> retired_attribute ~context "key" "json.key"
      | "default" -> retired_attribute ~context "default" "json.default"
      | "yojson.null" -> retired_attribute ~context "yojson.null" "json.null"
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

(** One field, decoded once. A missing key applies [@json.default], or [None] for an
    option with no default; a required field is the missing-field error. The expression
    does not contain the remaining decoder. The previous form spliced the continuation
    into both the missing branch and the success branch of every defaulted or optional
    field, so generated size was exponential in those fields (lindec-ho00). *)
let decode_one_field env parent_path (field : field_info) =
  let sub = Printf.sprintf "(%s ^ %S)" parent_path ("." ^ field.key) in
  let missing =
    match field.default with
    | Some expr -> Printf.sprintf "(Ok (%s))" expr
    | None when is_option_type field.fty -> "(Ok None)"
    | None ->
        Printf.sprintf "(Error (%s ^ \": missing field \" ^ %S))" parent_path field.key
  in
  Printf.sprintf
    "(match Stdlib.List.assoc_opt %S _ppx_yojson_fields with None -> %s | Some \
     _ppx_yojson_j -> %s)"
    field.key missing
    (decode env field.fty ~path:sub "_ppx_yojson_j")

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
    | field :: rest ->
        (* Bind this field, then decode the next. The continuation occurs once, in the
           [Ok] branch, so a default or an absent option cannot duplicate it. Earlier
           [_ppx_yojson_v_*] bindings stay in scope, which is where a later default
           expression already ran (lindec-ho00 lindec-nt5k). *)
        Printf.sprintf
          "(let _ppx_yojson_r_%s = %s in match _ppx_yojson_r_%s with Error _ppx_yojson_e \
           -> Error _ppx_yojson_e | Ok _ppx_yojson_v_%s -> %s)"
          field.fname
          (decode_one_field env parent_path field)
          field.fname field.fname (chain parent_path rest)
  in
  Printf.sprintf
    "(match _ppx_yojson_json with `Assoc _ppx_yojson_fields -> %s | _ -> Error %s)"
    (chain "_ppx_yojson_path" fields)
    (error_at ~path:"_ppx_yojson_path" "object" "_ppx_yojson_json")

let wire_name type_name (ctor : Parsetree.constructor_declaration) =
  let context =
    Printf.sprintf "type %s constructor %s" type_name ctor.Parsetree.pcd_name.txt
  in
  List.iter
    (fun attr ->
      if attr.Parsetree.attr_name.txt = "name" then
        retired_attribute ~context "name" "json.name")
    ctor.Parsetree.pcd_attributes;
  let names =
    List.filter
      (fun attr -> attr.Parsetree.attr_name.txt = "json.name")
      ctor.Parsetree.pcd_attributes
  in
  match names with
  | [] -> ctor.Parsetree.pcd_name.txt
  | [ attr ] -> (
      match string_of_key_payload attr with
      | Some name -> name
      | None -> failf "%s: [@json.name] expects a string literal" context)
  | _ -> failf "%s: duplicate [@json.name]" context

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

(** Encoder-only generation never evaluates a decoder generator, even for validation:
    constituent types need only their encoder. Bidirectional wrappers follow the group
    chain because simultaneous non-recursive bindings cannot see each other. *)
let gen_structure_decl env mode (decl : Parsetree.type_declaration) :
    string list * string list =
  let name = check_decl decl in
  let empty_record = is_empty_record decl in
  let allow_extra_fields = allows_extra_fields decl in
  if empty_record && allow_extra_fields then
    failf "type %s: [@@yojson.empty_record] cannot allow extra fields" name;
  let decoder generate =
    match mode with Encoder_only -> None | Bidirectional -> Some (generate ())
  in
  let encoded, decoded =
    if empty_record then
      ( "(`Assoc [])",
        decoder (fun () ->
            Printf.sprintf
              "(match _ppx_yojson_json with `Assoc _ppx_yojson_fields -> %s | _ -> Error \
               %s)"
              (reject_unknown_fields [] "(Ok ())")
              (error_at ~path:"_ppx_yojson_path" "object" "_ppx_yojson_json")) )
    else
      match decl.Parsetree.ptype_kind with
      | Parsetree.Ptype_record labels ->
          let fields = List.map (field_of_label env) labels in
          ( encode_record env fields "_ppx_yojson_v",
            decoder (fun () -> decode_record env ~allow_extra_fields fields) )
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
          let enc_cases =
            String.concat " | " (List.map (encode_constructor env name) ctors)
          in
          ( Printf.sprintf "(match _ppx_yojson_v with %s)" enc_cases,
            decoder (fun () ->
                let tags = String.concat " | " (List.map (Printf.sprintf "%S") names) in
                let cases =
                  String.concat " "
                    (List.map (decode_constructor env name "_ppx_yojson_path") ctors)
                in
                Printf.sprintf "(match _ppx_yojson_json with %s | _ -> Error %s)" cases
                  (error_at ~path:"_ppx_yojson_path" tags "_ppx_yojson_json")) )
      | Parsetree.Ptype_abstract -> (
          match decl.Parsetree.ptype_manifest with
          | Some core ->
              ( encode env core "_ppx_yojson_v",
                decoder (fun () ->
                    decode env core ~path:"_ppx_yojson_path" "_ppx_yojson_json") )
          | None -> failf "type %s: abstract implementation types cannot derive JSON" name
          )
      | Parsetree.Ptype_open ->
          failf "type %s: extensible variant types are not supported" name
      | Parsetree.Ptype_record_unboxed_product _ ->
          failf "type %s: unboxed record products are not supported" name
  in
  let encoder =
    Printf.sprintf "yojson_of_%s (_ppx_yojson_v : %s) : Yojson.Safe.t = %s" name name
      encoded
  in
  match decoded with
  | None -> ([ encoder ], [])
  | Some decoded ->
      ( [
          encoder;
          Printf.sprintf
            "ppx_yojson_decode_%s (_ppx_yojson_path : string) (_ppx_yojson_json : \
             Yojson.Safe.t) : (%s, string) result = %s"
            name name decoded;
        ],
        [
          Printf.sprintf
            "let %s_of_yojson (_ppx_yojson_json : Yojson.Safe.t) : (%s, string) result = \
             ppx_yojson_decode_%s %S _ppx_yojson_json"
            name name name name;
        ] )

let gen_signature_decl env mode (decl : Parsetree.type_declaration) : string list =
  let name = check_decl decl in
  (match (decl.Parsetree.ptype_kind, decl.Parsetree.ptype_manifest) with
  | Parsetree.Ptype_abstract, None -> (
      ignore (is_empty_record decl);
      match mode with
      | Encoder_only -> ()
      | Bidirectional -> failf "type %s: abstract types cannot derive yojson" name)
  | _ ->
      (* Signatures reject the same unsupported concrete shapes and attributes as
         implementations; emitting vals alone must not partially accept them. *)
      ignore (gen_structure_decl env mode decl));
  let encoder = Printf.sprintf "val yojson_of_%s : %s -> Yojson.Safe.t" name name in
  match mode with
  | Encoder_only -> [ encoder ]
  | Bidirectional ->
      [
        encoder;
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

type group_kind = Structure | Signature

type group = {
  decls : Parsetree.type_declaration list;
  mode : mode;
  kind : group_kind;
  recursive : bool;
  prelude : bool;
  line : int;
  blanks : (int * int) list;
  insert_at : int;
  insert_line : int;
}

let blanks_of_decl ~source (decl : Parsetree.type_declaration) : (int * int) list =
  List.filter_map
    (fun attr ->
      if is_deriving attr then
        match classify_deriving_payload attr.Parsetree.attr_payload with
        | Yojson _ -> Some (attribute_span ~source attr)
        | Other name ->
            failf
              "[@@deriving %s] is not supported: only [@@deriving yojson] or [@@deriving \
               yojson_of] is"
              name
        | Complex ->
            failf "unsupported [@@deriving] payload: write one deriver per attribute"
      else if
        is_allow_extra_fields attr || attr.Parsetree.attr_name.txt = "yojson.empty_record"
      then Some (attribute_span ~source attr)
      else None)
    decl.Parsetree.ptype_attributes

let line_of_decl (decl : Parsetree.type_declaration) =
  decl.Parsetree.ptype_loc.Location.loc_start.pos_lnum

let line_at_offset source offset =
  let line = ref 1 in
  for i = 0 to offset - 1 do
    if source.[i] = Char.chr 10 then incr line
  done;
  !line

(** A type group inherits its one requested mode, including unannotated members.
    Conflicting modes in the same recursive group are rejected, not partly derived. *)
let group_of_decls ~source ~kind ~recursive ~insert_at decls =
  let modes =
    List.concat_map
      (fun decl ->
        List.filter_map
          (fun attr ->
            if is_deriving attr then
              match classify_deriving_payload attr.Parsetree.attr_payload with
              | Yojson mode -> Some mode
              | Other name -> failf "[@@deriving %s] is not supported" name
              | Complex ->
                  failf
                    "unsupported [@@deriving] payload: write one deriver per attribute"
            else None)
          decl.Parsetree.ptype_attributes)
      decls
  in
  match modes with
  | [] -> None
  | mode :: rest ->
      if List.exists (( <> ) mode) rest then
        failf "a type group cannot mix [@@deriving yojson] and [@@deriving yojson_of]";
      Some
        {
          decls;
          mode;
          kind;
          recursive;
          prelude = false;
          line = line_of_decl (List.hd decls);
          blanks = List.concat_map (blanks_of_decl ~source) decls;
          insert_at;
          insert_line = line_at_offset source insert_at;
        }

(** The compiler iterator reaches modules in expressions as well as declarations. Ordinary
    structures/signatures are collected at their own source offsets. Unsupported module
    forms carry a rejection context through their entire subtree, so a functor argument or
    a packed/local module cannot be partially generated or silently missed. *)
let collect ~source tree =
  let groups = ref [] in
  let blocked = ref None in
  let needs_prelude = ref true in
  let allowed_attrs = Hashtbl.create 16 in
  let default = Ast_iterator.default_iterator in
  let within reason visit =
    let previous = !blocked in
    if Option.is_none previous then blocked := Some reason;
    Fun.protect ~finally:(fun () -> blocked := previous) visit
  in
  let add kind rec_flag loc decls =
    match !blocked with
    | Some _ -> () (* The attribute visitor reports the unsupported context. *)
    | None -> (
        match
          group_of_decls ~source ~kind
            ~recursive:(rec_flag = Asttypes.Recursive)
            ~insert_at:loc.Location.loc_end.pos_cnum decls
        with
        | None -> ()
        | Some group ->
            let prelude =
              group.kind = Structure && group.mode = Bidirectional && !needs_prelude
            in
            if prelude then needs_prelude := false;
            groups := { group with prelude } :: !groups;
            List.iter
              (fun decl ->
                List.iter
                  (fun attr ->
                    if is_deriving attr then
                      Hashtbl.replace allowed_attrs
                        attr.Parsetree.attr_loc.Location.loc_start.pos_cnum ())
                  decl.Parsetree.ptype_attributes)
              decls)
  in
  let iterator =
    {
      default with
      structure =
        (fun self items ->
          let previous = !needs_prelude in
          needs_prelude := true;
          Fun.protect
            ~finally:(fun () -> needs_prelude := previous)
            (fun () -> default.structure self items));
      structure_item =
        (fun self item ->
          match item.Parsetree.pstr_desc with
          | Parsetree.Pstr_type (rec_flag, decls) ->
              add Structure rec_flag item.Parsetree.pstr_loc decls;
              default.structure_item self item
          | Parsetree.Pstr_recmodule _ ->
              within "recursive modules" (fun () -> default.structure_item self item)
          | _ -> default.structure_item self item);
      signature_item =
        (fun self item ->
          match item.Parsetree.psig_desc with
          | Parsetree.Psig_type (rec_flag, decls) ->
              add Signature rec_flag item.Parsetree.psig_loc decls;
              default.signature_item self item
          | Parsetree.Psig_recmodule _ ->
              within "recursive modules" (fun () -> default.signature_item self item)
          | Parsetree.Psig_typesubst _ ->
              within "type substitutions" (fun () -> default.signature_item self item)
          | _ -> default.signature_item self item);
      module_expr =
        (fun self expr ->
          let visit () = default.module_expr self expr in
          match expr.Parsetree.pmod_desc with
          | Parsetree.Pmod_functor _ -> within "functors" visit
          | Parsetree.Pmod_apply _ | Parsetree.Pmod_apply_unit _ ->
              within "module applications" visit
          | Parsetree.Pmod_unpack _ -> within "first-class modules" visit
          | Parsetree.Pmod_extension _ -> within "module extensions" visit
          | _ -> visit ());
      module_type =
        (fun self ty ->
          let visit () = default.module_type self ty in
          match ty.Parsetree.pmty_desc with
          | Parsetree.Pmty_functor _ -> within "functors" visit
          | Parsetree.Pmty_with _ | Parsetree.Pmty_typeof _ | Parsetree.Pmty_strengthen _
            ->
              within "non-ordinary module types" visit
          | Parsetree.Pmty_extension _ -> within "module extensions" visit
          | _ -> visit ());
      expr =
        (fun self expr ->
          let visit () = default.expr self expr in
          match expr.Parsetree.pexp_desc with
          | Parsetree.Pexp_pack _ -> within "first-class modules" visit
          | Parsetree.Pexp_letmodule _ -> within "local modules" visit
          | _ -> visit ());
      attribute =
        (fun self attr ->
          (if is_deriving attr then
             match classify_deriving_payload attr.Parsetree.attr_payload with
             | Yojson _ -> (
                 match !blocked with
                 | Some context ->
                     failf "JSON derivation inside %s is not supported" context
                 | None ->
                     if
                       not
                         (Hashtbl.mem allowed_attrs
                            attr.Parsetree.attr_loc.Location.loc_start.pos_cnum)
                     then failf "JSON derivation is only supported on type declarations")
             | Other _ | Complex -> ());
          default.attribute self attr);
    }
  in
  (match tree with
  | `Structure items -> iterator.structure iterator items
  | `Signature items -> iterator.signature iterator items);
  List.sort (fun a b -> Int.compare a.insert_at b.insert_at) !groups

(* ---------- Assembly and entry point ---------- *)

(** Splice the generated converters into the source right after the type declaration that
    requested them, blanking the attribute spans. A [#]-line directive after each insert
    restores the original numbering, so errors in the surrounding code still point at the
    right lines. *)
let assemble ~source ~filename blanks groups codes =
  let bytes = Bytes.of_string source in
  List.iter
    (fun (start, stop) ->
      for i = start to stop - 1 do
        if Bytes.get bytes i <> '\n' && Bytes.get bytes i <> '\r' then
          Bytes.set bytes i ' '
      done)
    blanks;
  let base = Bytes.to_string bytes in
  let out = Buffer.create (String.length source + 4096) in
  let pos = ref 0 in
  List.iter
    (fun (group, code) ->
      Buffer.add_substring out base !pos (group.insert_at - !pos);
      pos := group.insert_at;
      Buffer.add_char out (Char.chr 10);
      Buffer.add_string out "(* Generated by ppx-yojson-minimal. Do not edit. *)\n";
      Buffer.add_string out "[@@@warning \"-32\"]\n";
      if group.prelude then Buffer.add_string out prelude;
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

let generate ~source ~filename groups =
  let blanks = List.concat_map (fun g -> g.blanks) groups in
  let codes =
    List.map
      (fun group ->
        let names = List.map (fun d -> d.Parsetree.ptype_name.txt) group.decls in
        (* A [type nonrec t = t] alias refers to its lexical parent codec, not itself. *)
        let env = { source; group = (if group.recursive then names else []) } in
        let located decl code =
          Printf.sprintf "# %d %S\n%s" (line_of_decl decl) filename code
        in
        match group.kind with
        | Signature ->
            String.concat "\n"
              (List.concat_map
                 (fun decl ->
                   List.map (located decl) (gen_signature_decl env group.mode decl))
                 group.decls)
        | Structure ->
            let mains, wraps =
              List.split
                (List.map
                   (fun decl ->
                     let mains, wraps = gen_structure_decl env group.mode decl in
                     (List.map (located decl) mains, List.map (located decl) wraps))
                   group.decls)
            in
            (if group.recursive then binding_of_group names group.decls else "let ")
            (* A directive must begin on its own line, even after [let] or [and]. *)
            ^ "\n"
            ^ String.concat "\nand\n" (List.concat mains)
            ^ "\n"
            ^ String.concat "\n" (List.concat wraps))
      groups
  in
  assemble ~source ~filename blanks groups codes

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
    | Some tree -> (
        match
          match collect ~source tree with
          | [] -> source
          | groups -> generate ~source ~filename groups
        with
        | output -> Ok output
        | exception Fail message -> Error (filename ^ ": " ^ message))
