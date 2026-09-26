type error = [ `Config of string ]
(** Config loading and schema validation. Reading may suspend or be cancelled; decoding is
    pure, and neither operation registers a finalizer. *)

type validation_error = { pointer : string; message : string }
(** One environment-dependent failure a validator found after decoding: [pointer] locates
    the field in the configuration's JSON form as a decode issue's does (RFC 6901), and
    [message] says what is wrong. A value: it owns no resource and registers no finalizer.
*)

val render_validation_errors : validation_error list -> string
(** [render_validation_errors errors] is the text the Door writes to stderr: each error as
    [message (pointer)], the pointer omitted when it is empty, joined by ["; "] — the
    style {!decode} renders its issues in. Pure; it neither suspends nor registers a
    finalizer. *)

val path :
  name:string -> config:string option -> getenv:(string -> string option) -> string
(** Resolve --config or XDG_CONFIG_HOME, falling back to HOME/.config. *)

val decode :
  schema:'a Eta_schema.t ->
  getenv:(string -> string option) ->
  string ->
  ('a, error) result
(** Parse TOML, apply schema-declared environment overrides, then validate. All decode
    issues, including unknown keys in closed schemas, retain JSON pointers. *)

val load :
  schema:'a Eta_schema.t ->
  getenv:(string -> string option) ->
  read:(string -> (string, string) result) ->
  path:string ->
  ('a, error) result
(** Read then decode; [read] is supplied by the Door to allow in-memory tests. *)
