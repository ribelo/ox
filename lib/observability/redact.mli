(** Redaction by type: a value every rendering path prints as ["<redacted>"].

    A secret is wrapped the moment it is read and travels as {!t}; the raw text
    is reachable only through {!expose}, which a caller has to write on purpose.
    {!pp}, {!to_string} and {!to_json} never show it, so a secret cannot reach a
    log line, a rendered record or a JSON document by accident. Logging a
    secret is therefore a change of type, not a convention on field names.

    Cancellation and finalizers: every function here is pure and synchronous.
    None performs I/O, blocks, forks a fiber or registers a finalizer, so no
    call can be interrupted and nothing is released afterwards. *)

type t
(** A value whose text never renders. The representation is abstract: only
    {!expose} reveals the wrapped string. *)

val make : string -> t
(** [make value] wraps [value]; it never renders [value] again. *)

val expose : t -> string
(** [expose t] is the wrapped text. This is the only revealing path, and it
    exists for the one place that legitimately needs the secret — building an
    ["Authorization"] header, for instance — never for a log line. *)

val pp : Format.formatter -> t -> unit
(** [pp fmt t] prints ["<redacted>"], never the wrapped text. *)

val to_string : t -> string
(** [to_string t] is ["<redacted>"], never the wrapped text. *)

val to_json : t -> Eta_json.t
(** [to_json t] is the JSON string ["<redacted>"], never the wrapped text. *)
