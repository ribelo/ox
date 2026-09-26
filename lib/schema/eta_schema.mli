@@ portable

(** Pure schemas and JSON codecs.

    An [eta_schema] value describes a data contract: it decodes a checked JSON value,
    encodes a typed value from the same description, derives equality, and derives
    provider JSON Schema. A decode or encode failure is an issue list, and every issue
    carries the path of the input that produced it. This package depends on the standard
    library alone.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards. *)

type path_segment : value mod portable = Field of string | Index of int

type issue_kind : value mod portable =
  | Type_mismatch of { expected : string; got : string }
  | Missing_field of string
  | Custom of string
  | Refinement_failed of { name : string; reason : string }

type issue : value mod portable = { path : path_segment list; schema_name : string option; kind : issue_kind }
(** A structured decode or validation problem.

    [path] is ordered from the outermost field/index to the innermost field/index.
    [schema_name] identifies the schema surface that produced the issue when the schema is
    named. [kind] is intended for programmatic classification; use {!render_issue} only
    for human-readable text. *)

(** Minimal JSON representation used by the core package. Adapters keep
    dependency-specific JSON values outside user schemas. *)
module Json : sig
  type number : value mod portable = Int of int | Intlit of string | Float of float

  type t : value mod portable = private
    | Null
    | Bool of bool
    | Number of number
    | String of string
    | Array of t list
    | Object of (string * t) list
        (** JSON value whose validity is established at construction.

            The representation is private: every constructor stays available for pattern
            matching, but only the checked constructors below build a [t]. A [t] therefore
            holds finite numbers, well-formed JSON number literals, and UTF-8 string
            values and object names; children of an [Array] or [Object] are already
            checked [t] values. *)

  val null : t
  val bool : bool -> t
  val int : int -> t

  val number : float -> (t, issue list) result
  (** [number value] is [Ok] for a finite [value] and an issue otherwise. *)

  val intlit : string -> (t, issue list) result
  (** [intlit literal] is [Ok] when [literal] is a JSON number literal and an issue
      otherwise. The literal is preserved exactly; it is never narrowed through [int] or
      [float]. *)

  val string : string -> (t, issue list) result
  (** [string value] is [Ok] when [value] is well-formed UTF-8 and an issue otherwise.
      Control characters are valid; serialization escapes them. *)

  val array : t list -> t
  (** Total: every element is already a checked [t]. *)

  val object_ : (string * t) list -> (t, issue list) result
  (** [object_ fields] is [Ok] when every name is well-formed UTF-8 and an issue carrying
      the offending name's path otherwise. Duplicate names and field order are preserved.
  *)

  val find : string -> t -> t option

  val equal : t -> t -> bool
  (** Constructor-sensitive structural equality. [Int], [Float], and [Intlit] compare only
      with the same constructor. [Float] uses [Float.equal], so signed zeros compare
      equal. Object fields are compared after sorting keys; arrays stay ordered. *)

  val to_string : t -> string
end

type json = Json.t

type error = [ `Decode of issue list | `Encode of issue list ]
(** Typed Eta error emitted by schema codecs. *)

val issue : ?path:path_segment list -> ?schema_name:string -> string -> issue

val type_mismatch :
  ?path:path_segment list ->
  ?schema_name:string ->
  expected:string ->
  got:string ->
  unit ->
  issue

val missing_field : ?path:path_segment list -> ?schema_name:string -> string -> issue
val at : path_segment -> issue list -> issue list
val at_field : string -> issue list -> issue list
val at_index : int -> issue list -> issue list
val render_issue : issue -> string
val render_issues : issue list -> string
val issue_to_json_pointer : issue -> string

val json_pointer : path_segment list -> string
(** [json_pointer path] renders a path as an RFC 6901 JSON Pointer: [""] for the empty
    path, [/a~1b/1] for a field named ["a/b"] followed by index 1. Field names escape [~]
    as [~0] and [/] as [~1]; an index renders in decimal. {!issue_to_json_pointer} is
    [json_pointer] applied to an issue's path. *)

val pp_issue : Format.formatter -> issue -> unit
(** [pp_issue fmt issue] prints one issue as {!render_issue} renders it. *)

val pp_issues : Format.formatter -> issue list -> unit
(** [pp_issues fmt issues] prints the ["; "]-separated rendering of a list. *)

val pp_error : Format.formatter -> error -> unit
(** [pp_error fmt error] prints [decode: <issues>] or [encode: <issues>], so a caller
    holding an {!error} can render it without matching the variant. *)

type 'a t
(** Pure schema/codec value: decode, encode, equality, provider JSON Schema, and the field
    marks declared by record builders. *)

val string : string t
val bool : bool t
val int : int t
val float : float t

val json : json t
(** Identity schema for arbitrary JSON values. Its provider JSON Schema is unconstrained.
*)

val json_object : (string * json) list t
(** Free-form JSON object schema. Provider metadata permits arbitrary properties while
    runtime decoding rejects non-object values. *)

val array : 'a t -> 'a list t
val option : 'a t -> 'a option t

val enum : name:string -> (string * 'a) list -> equal:('a -> 'a -> bool) -> 'a t
(** String-backed closed variant schema. *)

type 'a case

val case :
  tag:string ->
  decode:(json -> ('a, issue list) result) ->
  encode:('a -> (json option, issue list) result) ->
  'a case

val tagged_union :
  name:string -> tag:string -> 'a case list -> equal:('a -> 'a -> bool) -> 'a t
(** Tagged-union schema for ordinary OCaml variants. Case encoders return [Ok None] when
    the value belongs to another case and [Error issues] when the selected case cannot
    encode its payload. *)

val lazy_ : (unit -> 'a t) -> 'a t
(** Recursive schema knot. *)

type 'a union_case

val union_case :
  'case t -> inject:('case -> 'a) -> project:('a -> 'case option) -> 'a union_case

val union_cases : name:string -> 'a union_case list -> equal:('a -> 'a -> bool) -> 'a t

val union : name:string -> 'a t list -> equal:('a -> 'a -> bool) -> 'a t
(** Untagged union tried in declaration order. The derived provider schema uses [anyOf].
*)

val custom :
  equal:('a -> 'a -> bool) ->
  decode:(json -> ('a, issue list) result) ->
  encode:('a -> (json, issue list) result) ->
  json_schema:json ->
  ?object_fields:string list ->
  unit ->
  'a t
(** Build a schema from explicit pure codecs and provider metadata. Prefer ordinary
    combinators when they can express the same contract. *)

type ('record, 'field) field

val required :
  ?secret:bool ->
  ?env:string ->
  string ->
  'field t ->
  ('record -> 'field) ->
  ('record, 'field) field

val optional :
  ?secret:bool ->
  ?env:string ->
  string ->
  'field t ->
  ('record -> 'field option) ->
  ('record, 'field option) field
(** A declared record field. [~secret:true] marks the field's value as a secret to redact
    in rendered output; [~env:"VAR"] declares that the environment variable [VAR] may
    override the field. Both marks travel with the field and are read back by
    {!field_marks}; neither changes decoding, encoding, or provider JSON Schema. *)

val record0 :
  name:string -> 'record -> equal:('record -> 'record -> bool) -> unit -> 'record t

val record1 :
  name:string ->
  ('a -> 'record) ->
  ('record, 'a) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t

val record2 :
  name:string ->
  ('a -> 'b -> 'record) ->
  ('record, 'a) field ->
  ('record, 'b) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t

val record3 :
  name:string ->
  ('a -> 'b -> 'c -> 'record) ->
  ('record, 'a) field ->
  ('record, 'b) field ->
  ('record, 'c) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t

val record4 :
  name:string ->
  ('a -> 'b -> 'c -> 'd -> 'record) ->
  ('record, 'a) field ->
  ('record, 'b) field ->
  ('record, 'c) field ->
  ('record, 'd) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t

val record5 :
  name:string ->
  ('a -> 'b -> 'c -> 'd -> 'e -> 'record) ->
  ('record, 'a) field ->
  ('record, 'b) field ->
  ('record, 'c) field ->
  ('record, 'd) field ->
  ('record, 'e) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t

val record6 :
  name:string ->
  ('a -> 'b -> 'c -> 'd -> 'e -> 'f -> 'record) ->
  ('record, 'a) field ->
  ('record, 'b) field ->
  ('record, 'c) field ->
  ('record, 'd) field ->
  ('record, 'e) field ->
  ('record, 'f) field ->
  equal:('record -> 'record -> bool) ->
  unit ->
  'record t
(** Arity-specific builders are the v0 hand-written product API. A PPX can generate these
    calls later without changing ['a t]. *)

type 'record member

val required_member :
  ?secret:bool ->
  ?env:string ->
  string ->
  'field t ->
  get:('record -> 'field) ->
  set:('record -> 'field -> 'record) ->
  'record member

val optional_member :
  ?secret:bool ->
  ?env:string ->
  string ->
  'field t ->
  get:('record -> 'field option) ->
  set:('record -> 'field option -> 'record) ->
  'record member
(** As {!required} and {!optional}: the dynamic-arity members carry the same [~secret] and
    [~env] marks. *)

val record_fields :
  name:string ->
  empty:'record ->
  equal:('record -> 'record -> bool) ->
  'record member list ->
  'record t
(** Dynamic-arity record builder for hand-written large product schemas. Members carry
    typed getters and setters; no heterogeneous values escape. *)

val refine : name:string -> ('a -> issue list) -> 'a t -> 'a t

val describe : string -> 'a t -> 'a t
(** Attach a JSON Schema description without changing codec behavior. *)

val with_keyword : string -> json -> 'a t -> 'a t
(** Attach or replace one JSON Schema keyword. Validation constraints should also be
    represented by [refine] so provider metadata and runtime validation remain one
    composed schema value. *)

val closed : 'a t -> 'a t
(** Reject fields not declared by an object record schema and derive
    [additionalProperties: false]. Raises [Invalid_argument] for non-object schemas. *)

val json_schema : 'a t -> json
(** Derive provider-facing JSON Schema from this codec value. *)

val transform :
  name:string ->
  equal:('a -> 'a -> bool) ->
  decode:('encoded -> ('a, issue list) result) ->
  encode:('a -> 'encoded) ->
  'encoded t ->
  'a t
(** Bidirectional schema transformation.

    This is the primitive for validated nominal types in OCaml. Prefer a domain-owned
    module with an abstract or private [type t] and a schema built from [transform],
    rather than a TypeScript-style public wrapper. *)

val decode_result : 'a t -> json -> ('a, issue list) result
(** Immediate pure decode. The codec runs during this call; ordinary exceptions it raises
    propagate to the caller. Every failing branch is reported, each issue carrying the
    path of the value that produced it. *)

val encode_result : 'a t -> 'a -> (json, issue list) result
(** Immediate pure encode from the schema {!decode_result} reads: replies and
    [config check] output use the declared shape. *)

val equal : 'a t -> 'a -> 'a -> bool

type field_mark = { pointer : string; name : string; secret : bool; env : string option }
(** One declared record field as metadata: [pointer] is its RFC 6901 JSON Pointer from the
    schema root (see {!json_pointer}), [name] is the field's own name, [secret] marks a
    value to redact, and [env] names the environment variable allowed to override the
    field. *)

val field_marks : 'a t -> field_mark list
(** [field_marks schema] is every record field [schema] declares, in declaration order.
    Nested record fields are flattened with their pointer prefix, so [pointer] is
    [/models/api_key] for a field two levels down. [array] and [option] do not change a
    pointer; enums, unions and {!custom} schemas declare no marks, because their field
    names are not statically known. *)

val encode_redacted : 'a t -> 'a -> (json, issue list) result
(** [encode_redacted schema value] is {!encode_result} with every secret-marked field
    replaced by the string ["<redacted>"]. The replacement walks the encoded document
    along each mark's pointer and descends into arrays, so a secret nested in
    [array (record ...)] is reached. Encoding failures are reported unchanged. *)

(** Adapter contract for concrete JSON libraries such as Yojson. The core package
    intentionally does not force one JSON dependency. *)
module type JSON_ADAPTER = sig
  type external_json

  val of_external : external_json -> (json, issue list) result
  val to_external : json -> external_json
end

(** Bind schemas to a concrete JSON representation through a {!JSON_ADAPTER}. *)
module Make (A : JSON_ADAPTER) : sig
  val decode_result : 'a t -> A.external_json -> ('a, issue list) result
  (** [decode_result schema external] converts [external] with {!of_external} and decodes
      the result. Issues from either stage are reported unchanged; nothing is deferred. *)

  val encode_result : 'a t -> 'a -> (A.external_json, issue list) result
  (** [encode_result schema value] encodes with the schema first and converts with
      {!to_external} only after the schema codec succeeded. *)
end
