(** Untyped JSON accessors shared by Eta packages.

    This module is the single owner of Eta's unchecked Yojson helpers: a bounded parse,
    compact serialization, scalar constructors, object and array builders, and
    option-returning member reads. Packages that only need a JSON value depend on this
    package instead of on a provider package.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards. *)

type t = Yojson.Safe.t
(** JSON values are exactly {!Yojson.Safe.t}. *)

type too_large = { limit : int; length : int }
(** The byte bound a refusal names and the length of the input it refused. *)

type parse_error = [ `Malformed of string | `Too_large of too_large ]
(** Why {!parse} refused a document: [`Malformed] carries Yojson's message for text that
    is not one JSON document, and [`Too_large] carries the byte bound and the input's
    actual length for input the bound refused before any JSON value was built. *)

val parse : ?max_bytes:int -> string -> (t, parse_error) result
(** [parse raw] is [Ok json] when [raw] is one complete JSON document, and a
    {!parse_error} when it is not. Malformed input is reported as a result, never as an
    exception.

    [max_bytes] rejects oversized input before Yojson sees it: when
    [String.length raw > max_bytes], [parse] is [Error (`Too_large _)] even for text that
    is valid JSON, and no JSON value is built. [`Too_large] is therefore only produced
    when the bound is set.

    @raise Invalid_argument
      when [max_bytes] is negative. A negative bound is a programming defect, not a parse
      failure. *)

val to_string : t -> string
(** [to_string json] is the compact JSON text of [json]: one line, no indentation, no
    whitespace outside strings. *)

val compact : t -> string
(** [compact] is {!to_string}: both emit the same compact text. *)

val pp_parse_error : Format.formatter -> parse_error -> unit
(** [pp_parse_error fmt error] renders a refusal as one line of text. *)

val string : string -> t
val bool : bool -> t
val int : int -> t

val float : float -> t option
(** [float value] is [Some (`Float value)] for a finite value and [None] for NaN or an
    infinity, which JSON cannot represent. *)

val array : t list -> t
(** [array values] is the JSON array of [values] in order. *)

val array_map : ('a -> t) -> 'a list -> t
(** [array_map f values] is [array (List.map f values)]: one JSON array holding [f]
    applied to every element, in input order. *)

val object_ : (string * t option) list -> t
(** [object_ fields] is the JSON object of [fields] in order. A field whose value is
    [None] is omitted; a [Some value] field keeps its name and its position. *)

val member : string -> t -> t option
(** [member name json] is the value stored under [name] when [json] is a JSON object, and
    [None] when the name is absent or [json] is not an object. *)

val string_member : string -> t -> string option
(** [string_member name json] is [Some value] only when the named member is a JSON string;
    every other member shape and an absent member are [None]. *)

val scalar_string_member : string -> t -> string option
(** [scalar_string_member name json] renders a scalar member as text: strings verbatim,
    integers in decimal, integer literals verbatim, floats with 17 significant digits, and
    booleans as ["true"] or ["false"]. An array, an object, null, and an absent member are
    [None]. *)

val int_member : string -> t -> int option
(** [int_member name json] is [Some value] for an integer member, for an integer literal
    that fits [int], and for a float whose value is an integer that round-trips through
    [int]. A float with a fractional part, any other member shape, and an absent member
    are [None]. *)

val array_member : string -> t -> t list option
(** [array_member name json] is [Some values] only when the named member is a JSON array;
    every other member shape and an absent member are [None]. *)

val object_member : string -> t -> t option
(** [object_member name json] is [Some member] only when the named member is a JSON
    object; every other member shape and an absent member are [None]. *)
