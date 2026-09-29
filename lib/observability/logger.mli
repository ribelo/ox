(** Structured logging: one JSON object per line, with the fiber's context.

    A {!record} carries a timestamp, a level, the service name, the message, the event's
    own fields, and the fields its fiber inherited from {!Context}. {!Reporter} decides
    where a record goes: {!Reporter.journal} writes one compact JSON object per line to an
    Eio sink — the Door passes stderr — {!Reporter.writer} calls a function with the same
    text, and {!Memory} keeps records for a test to query.

    The line is the contract with [journalctl]: one object per line, keys in a fixed
    order, and no whitespace outside strings.

    {v
    {"ts":"2026-09-26T12:52:49.123Z","level":"warn","service":"leash",
     "msg":"reconnect","fields":{"attempt":3},"context":{"tab":"t-1"}}
    v}

    The order is [ts], [level], [service], [msg], [fields], [context]; [fields] and
    [context] are sorted by name and omitted when empty. [ts] is UTC with millisecond
    precision, computed from the supplied wall clock by arithmetic alone — this package
    never reads the operating system's idea of a calendar. [fields] values are JSON
    scalars, a nested JSON value, or ["<redacted>"] for a {!Redact.t}.

    {[
    let logger =
      Logger.create ~service:"leash" ~clock:env#clock ~mono_clock:env#mono_clock
        ~reporter:(Logger.Reporter.journal (Eio.Stdenv.stderr env))
        ()
    in
    Context.with_fields [ ("tab", "t-1") ] @@ fun () ->
    Logger.info logger ~fields:[ ("owner", Logger.String "rafal") ] "attached"
    ]}

    Cancellation and finalizers: logging takes no switch, forks no fiber and registers no
    finalizer. {!log} and {!span} read the inherited context, which performs Eio's
    [Get_context] effect, so they belong to an Eio fiber; outside one the inherited
    context is empty. A write to an Eio sink can suspend and can therefore be interrupted,
    and a cancelled write raises [Eio.Cancel.Cancelled] like any other Eio operation —
    except on {!span}'s exception path, where writing is best effort and the span's own
    exception always propagates. *)

type level = Debug | Info | Warn | Error

val pp_level : Format.formatter -> level -> unit
(** [pp_level] prints [debug], [info], [warn] or [error]. *)

val level_to_string : level -> string
(** [level_to_string level] is the name {!pp_level} prints. *)

type value =
  | String of string
  | Int of int
  | Float of float
  | Bool of bool
  | Json of Ox_json.t
  | Redacted of Redact.t
      (** A field's value. [Redacted] renders as ["<redacted>"] on every path, so a secret
          is logged as a value of this type or not at all. *)

val pp_value : Format.formatter -> value -> unit
(** [pp_value] prints a value as text: the string itself for {!String}, decimal for
    {!Int}, [%g] for {!Float}, [true] or [false] for {!Bool}, compact JSON for {!Json},
    and ["<redacted>"] for {!Redacted}. This is the text {!Memory.find}'s [field] query
    matches, not the JSON encoding. *)

val value_to_json : value -> Ox_json.t
(** [value_to_json value] is the JSON encoding of a field value. A non-finite {!Float}
    becomes a JSON string, because JSON has no NaN or infinity. *)

type record = {
  ts : float;  (** seconds since the epoch, read from the logger's wall clock *)
  level : level;
  service : string;
  msg : string;
  fields : (string * value) list;  (** sorted by name, no duplicate names *)
  context : (string * string) list;  (** sorted by name *)
}
(** One log record: what a line is made of, and what a test queries. *)

val to_json : record -> Ox_json.t
(** [to_json record] is the object {!to_string} writes. *)

val to_string : record -> string
(** [to_string record] is the compact JSON line for [record], without the trailing
    newline: one line, fixed key order, no whitespace outside strings. *)

(** Where records go. *)
module Reporter : sig
  type t

  val journal : [> Eio.Flow.sink_ty ] Eio.Flow.sink -> t
  (** [journal sink] writes each record to [sink] as one compact JSON line, including its
      newline, and serializes concurrent writers with a mutex so two fibers cannot
      interleave halves of a line. The Door passes [Eio.Stdenv.stderr]; the sink is used
      until the program ends and no finalizer is registered on it. *)

  val records : (record -> unit) -> t
  (** [records consume] receives the typed record without serializing it; an exporter
      can use it without making observability depend on any transport. ^notel-6m2q *)

  val writer : (string -> unit) -> t
  (** [writer write_line] calls [write_line] once per record with the same text {!journal}
      writes. The caller owns synchronization and the newline is included in the argument.
  *)

  val at_least : level -> t -> t
  (** [at_least level reporter] forwards only records at or above [level] to [reporter].
      Other reporters and the logger's own minimum level are unaffected. ^napp-xb3q *)

  val tee : t list -> t
  (** [tee reporters] delivers each record to every reporter in [reporters], in the order
      given, so a journal and an exporter coexist: a reporter that raises is skipped and
      the later ones still receive the record. [Eio.Cancel.Cancelled] propagates — an
      interruption is the logging fiber's, not a reporter failure — and a reporter's
      exception is otherwise contained, so a broken exporter cannot break logging. Pure:
      it captures the list and registers no finalizer. ^nobs-8i5y *)
end

(** An in-memory reporter for tests. *)
module Memory : sig
  type t

  val create : unit -> t
  (** [create ()] is an empty store. *)

  val reporter : t -> Reporter.t
  (** [reporter store] is a reporter that keeps every record in [store]. *)

  val records : t -> record list
  (** [records store] is every record kept so far, in the order it was logged. A snapshot:
      logging afterwards does not change the returned list. *)

  val find : ?level:level -> ?field:string * string -> t -> record list
  (** [find ?level ?field store] is the kept records matching every supplied criterion, in
      the order they were logged. [level] matches the record's level exactly;
      [field (name, text)] matches when the record has a field called [name] whose
      {!pp_value} rendering is [text]. A redacted value renders as ["<redacted>"], so a
      test can assert that a field is redacted without knowing the secret. *)
end

type limit
(** A ceiling on how often one message may be written. *)

val limit : max:int -> window:Ox.Duration.t -> limit
(** [limit ~max ~window] admits at most [max] records carrying one message text per
    [window], measured on the logger's monotonic clock. The window starts at the first
    admitted record and resets [window] after it; a dropped record is counted nowhere and
    written nowhere.
    @raise Invalid_argument if [max] is less than 1 or [window] is not positive. *)

type t
(** A logger: its reporter, its minimum level, its base fields and its clocks. *)

val create :
  ?level:level ->
  ?fields:(string * value) list ->
  ?span_ids:(unit -> string) ->
  service:string ->
  clock:_ Eio.Time.clock ->
  mono_clock:_ Eio.Time.Mono.t ->
  reporter:Reporter.t ->
  unit ->
  t
(** [create ~service ~clock ~mono_clock ~reporter ()] is a logger that reads journal
    timestamps from [clock] (the wall clock the Door passes) and measures spans and
    rate-limit windows on [mono_clock]. [level] is the minimum level this logger writes,
    [Info] by default; [fields] are attached to every record it writes, and a record's own
    field with the same name wins. A base field with the same name as an inherited context
    field is unaffected: they render as separate objects. [span_ids], when supplied,
    generates exactly 32 lowercase hexadecimal digits per call: a new trace takes
    32 digits, and each span takes the first 16 digits of a fresh ID. Nested spans inherit their trace_id and
    parent_span_id; absent [span_ids], existing behavior is unchanged.
    ^nobs-xovg ^notel-6m2q *)

val enabled : t -> level -> bool
(** [enabled logger level] is [true] when a record of that level would pass the logger's
    minimum level. *)

val log :
  t ->
  level ->
  msg:string ->
  ?fields:(string * value) list ->
  ?limit:limit ->
  unit ->
  unit
(** [log logger level ~msg ?fields ?limit ()] writes one record with the current
    {!Context} fields when [level] passes the logger's minimum and [limit] admits the
    message. *)

val debug : t -> ?fields:(string * value) list -> ?limit:limit -> string -> unit
(** [debug logger msg] is [log logger Debug ~msg ()]. *)

val info : t -> ?fields:(string * value) list -> ?limit:limit -> string -> unit
(** [info logger msg] is [log logger Info ~msg ()]. *)

val warn : t -> ?fields:(string * value) list -> ?limit:limit -> string -> unit
(** [warn logger msg] is [log logger Warn ~msg ()]. *)

val error : t -> ?fields:(string * value) list -> ?limit:limit -> string -> unit
(** [error logger msg] is [log logger Error ~msg ()]. *)

val span :
  t ->
  ?level:level ->
  ?fields:(string * value) list ->
  ?pp_err:(Format.formatter -> 'e -> unit) ->
  string ->
  (unit -> ('a, 'e) result) ->
  ('a, 'e) result
(** [span logger name f] logs the start and the end of one unit of work and returns what
    [f ()] returned: tracing as structured logs, before any exporter exists.
    [f] is global because optional IDs bind through [Context.with_fields] into
    [Eio.Fiber.with_binding], which requires a global callback (nmodes-8t8v, nmodes-8y46).

    Both records carry [name] as their message, [event] as ["start"] or ["end"], the
    span's own [fields] and the fiber's inherited context. The end record also carries
    [elapsed_ms], measured on the monotonic clock, and [outcome]:
    - ["ok"] when [f] returned [Ok], at the span's [level];
    - ["failed"] when [f] returned [Error e], at [Error] level, with the typed failure
      rendered as [error] through [Cause.pp_compact] and [pp_err];
    - ["defect"] when [f] raised, at [Error] level, with the exception rendered as [error]
      through [Cause.pp_compact]; the exception is re-raised with its original backtrace
      after the record is written;
    - ["interrupt"] when [f] raised [Eio.Cancel.Cancelled], at the span's [level]; the
      interruption is re-raised with its original backtrace.

    A record the logger's minimum level drops is not written; a span in a logger whose
    minimum is [Warn] therefore writes only the end record of a failure. [pp_err] renders
    the typed payload of a failure; without it the summary names the cause and prints
    ["<error>"] in place of the payload. On the exception path the end record is written
    best effort: a reporter that raises cannot replace the exception that is already
    propagating. *)
