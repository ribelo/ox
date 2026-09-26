(** Yojson adapter for {!Eta_schema}.

    Cancellation and finalizers: every function here is pure and synchronous.
    None performs I/O, blocks, forks a fiber, or registers a finalizer, so no
    call can be interrupted and nothing is released afterwards. *)

type external_json = Yojson.Safe.t
(** Yojson values are exactly {!Yojson.Safe.t}. *)

val of_yojson :
  external_json -> (Eta_schema.json, Eta_schema.issue list) result
(** Convert external Yojson into the checked {!Eta_schema.Json.t}.

    Conversion attaches the input location while it descends: a failing array
    element carries its zero-based index and a failing object field carries its
    stored name, outermost to innermost, so
    {!Eta_schema.issue_to_json_pointer} reports [""], [/0/1], or [/a~1b/1] for
    the root, nested-array, and field-plus-index cases. Names are stored
    unescaped and escaped only when rendered.

    Invalid data (non-finite floats, malformed number literals, malformed UTF-8
    string values or object names, non-standard Yojson extensions) returns
    issues. Exceptions raised by caller code are not caught and turned into
    validation issues. *)

val to_yojson : Eta_schema.json -> external_json
(** [to_yojson json] is the Yojson value of a checked schema value. Conversion
    is total: {!Eta_schema.Json.t} holds only representable data. *)

val decode_result :
  'a Eta_schema.t ->
  external_json ->
  ('a, Eta_schema.issue list) result
(** [decode_result schema external] converts [external] with {!of_yojson} and
    decodes the result with the schema. Issues from either stage carry the
    input's path and are reported unchanged. *)

val encode_result :
  'a Eta_schema.t ->
  'a ->
  (external_json, Eta_schema.issue list) result
(** [encode_result schema value] encodes [value] with the same schema and only
    then converts to Yojson. *)
