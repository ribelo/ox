type error = [ `Config of string ]
(** Config loading. Reading may suspend or be cancelled; decoding and the environment
    overrides are pure, and no operation registers a finalizer. *)

type validation_error = { pointer : string; message : string }
(** One environment-dependent failure a validator found after decoding: [pointer] locates
    the field in the configuration's JSON form as a decode issue's does (RFC 6901), and
    [message] says what is wrong. A value: it owns no resource and registers no finalizer.
*)

val render_validation_errors : validation_error list -> string
(** [render_validation_errors errors] is the text the Door writes to stderr: each error as
    [message (pointer)], the pointer omitted when it is empty, joined by ["; "]. Pure; it
    neither suspends nor registers a finalizer. *)

type 'cfg t = {
  of_yojson : Yojson.Safe.t -> ('cfg, string) result;
      (** The derived decoder: [Settings.settings_of_yojson] for a config type named
          [settings], or [Config.t_of_yojson] for [Leash.Config.t]. Its error is the
          deriver's message — the dotted path of the offending value and the value itself,
          bounded. *)
  yojson_of_t : 'cfg -> Yojson.Safe.t;
      (** The derived encoder, used by [config check] to print the effective
          configuration. A secret field of type {!Eta_observability.Redact.t} encodes as
          ["<redacted>"]. *)
  env : getenv:(string -> string option) -> 'cfg -> 'cfg;
      (** Environment overrides, applied to the decoded value: a field the service reads
          from the environment can only be supplied here after decoding, so a field with
          no file value is an [option] or carries [[@json.default]]. An override that
          cannot be parsed is ignored; bounds belong in the Door's validator. *)
}

val path :
  name:string -> config:string option -> getenv:(string -> string option) -> string
(** Resolve --config or XDG_CONFIG_HOME, falling back to HOME/.config. *)

val decode :
  spec:'cfg t -> getenv:(string -> string option) -> string -> ('cfg, error) result
(** Parse TOML, convert it to [Yojson.Safe.t], decode with [spec.of_yojson], then apply
    [spec.env]. TOML dates and non-finite floats are refused with the JSON pointer of the
    value; a decode failure is the deriver's message unchanged. *)

val load :
  spec:'cfg t ->
  getenv:(string -> string option) ->
  read:(string -> (string, string) result) ->
  path:string ->
  ('cfg, error) result
(** Read then decode; [read] is supplied by the Door to allow in-memory tests. *)
