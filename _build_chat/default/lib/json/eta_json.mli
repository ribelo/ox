@@ portable

(** Untyped JSON accessors shared by Eta packages.

    This module is the single owner of Eta's unchecked Yojson helpers: a bounded parse,
    compact serialization, scalar constructors, object and array builders, option-returning
    member reads, and the {!Of_json} decoder combinators for JSON whose shape is not a
    type. Packages that only need a JSON value depend on this package instead of on a
    provider package.

    Cancellation and finalizers: every function here is pure and synchronous. None
    performs I/O, blocks, forks a fiber, or registers a finalizer, so no call can be
    interrupted and nothing is released afterwards. *)

type t : value mod portable = Yojson.Safe.t
(** JSON values are exactly {!Yojson.Safe.t}. *)

type too_large = { limit : int; length : int }
(** The byte bound a refusal names and the length of the input it refused. *)

type parse_error = [ `Malformed of string | `Too_large of too_large ]
(** Why {!parse} refused a document: [`Malformed] carries Yojson's message for text that
    is not one JSON document, and [`Too_large] carries the byte bound and the input's
    actual length for input the bound refused before any JSON value was built. *)

val parse : ?max_bytes:int -> string -> (t, parse_error) result @@ nonportable
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

val to_string : t -> string @@ nonportable
(** [to_string json] is the compact JSON text of [json]: one line, no indentation, no
    whitespace outside strings. *)

val compact : t -> string @@ nonportable
(** [compact] is {!to_string}: both emit the same compact text. *)

val pp_parse_error : Format.formatter -> parse_error -> unit
(** [pp_parse_error fmt error] renders a refusal as one line of text. *)

type issue = { path : string; message : string; got : t }
(** Why an {!Of_json} decoder refused a value: [path] locates the value with the deriver's
    dotted path ([user.name], [tags.[1]]) and is empty when the value decoded is the whole
    document, [message] says what was expected there, and [got] is the value itself. A
    value: it owns no resource and registers no finalizer. *)

val pp_issue : Format.formatter -> issue -> unit @@ nonportable
(** [pp_issue fmt issue] renders the issue on one line as [path: message, got <subtree>],
    the path omitted when it is empty and the subtree compacted and bounded to 200
    characters. Nonportable because it renders the subtree through {!to_string}; the
    decoders of {!Of_json} build the issue as data and render nothing. *)

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

(** Decoder combinators in jsonkit's [Of_json] shape: a decoder is a plain function from a
    JSON value to a result and a builder takes decoders, so a document is read by
    composing functions instead of nesting {!member} calls. ^nderive-vq4n

    A failure is an {!issue}, never an exception, and it carries the path of the failing
    value: {!Of_json.field} prefixes the name it read and {!Of_json.list} appends the
    element index, so [field "args" (field "index" int)] reports [args.index].

    Every function here is pure, synchronous and portable: none performs I/O, blocks,
    forks a fiber, or registers a finalizer, so no call can be interrupted, and a failure
    is built as an {!issue} rather than rendered. *)
module Of_json : sig
  type 'a t = Yojson.Safe.t -> ('a, issue) result
  (** A decoder: the value it read, or the {!issue} saying why the JSON does not fit. *)

  val string : string t
  (** Accepts a JSON string. *)

  val bool : bool t
  (** Accepts a JSON boolean. *)

  val int : int t
  (** Accepts a JSON integer, including an integer literal that fits [int]: the same
      coercion the deriver makes. *)

  val float : float t
  (** Accepts a JSON number: a float, or an integer widened to [float]. *)

  val null : unit t
  (** Accepts [null]. *)

  val list : 'a t -> 'a list t
  (** [list decoder] accepts a JSON array every element of which [decoder] accepts. A
      failing element's issue is at that element's path ([tags.[1]]). *)

  val option : 'a t -> 'a option t
  (** [option decoder] accepts [null] as [None] and anything [decoder] accepts as [Some]:
      the explicit-null encoding. A [decoder] failure is reported, not turned into [None];
      {!try_or_none} is the combinator that does that. *)

  val field : string -> 'a t -> 'a t
  (** [field name decoder] reads the object member [name] and decodes it with [decoder].
      A non-object input, and a missing member, are reported at the path of the object
      itself. *)

  val at : string list -> 'a t -> 'a t
  (** [at names decoder] is {!field} applied to each name in turn: [at ["a"; "b"] decoder]
      reads the member [b] of the member [a]. *)

  val one_of : 'a t list -> 'a t
  (** [one_of alternatives] is the first alternative that accepts the value; when every
      alternative fails, the issue is at the value's own path and says it matched none of
      them. *)

  val try_or_none : 'a t -> 'a option t
  (** [try_or_none decoder] is [Some] of what [decoder] accepts and [None] when [decoder]
      fails, so a member that may be absent, [null], or of another shape reads as an
      option. *)
end
