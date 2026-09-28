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

type read_error = [ `Missing | `Unreadable of string ]
(** Why reading the config file failed: [`Missing] is nothing at that path,
    [`Unreadable message] a path that exists and could not be read. The Door's rule turns
    on the difference, so a reader that cannot tell them apart cannot supply it.
    ^napp-9x0s *)

type missing = [ `Defaults | `Required ]
(** Whether the default source may be absent. An explicit path is always required. *)

type source = [ `Default of string | `Explicit of string ]
(** Where the config text comes from: [`Explicit] is a path the operator passed with
    --config, [`Default] the path {!path} resolves for the service's name. Only the latter
    may be absent. A value: it owns no resource. ^napp-9x0s *)

val path :
  name:string -> config:string option -> getenv:(string -> string option) -> string

val path_with :
  file_name:string ->
  name:string ->
  config:string option ->
  getenv:(string -> string option) ->
  string
(** Resolve --config or XDG_CONFIG_HOME, falling back to HOME/.config. *)

val resolve :
  name:string -> config:string option -> getenv:(string -> string option) -> source

val resolve_with :
  file_name:string ->
  name:string ->
  config:string option ->
  getenv:(string -> string option) ->
  source
(** [resolve] is {!path} with its origin kept, which is what {!load} needs to decide
    whether an absent file is allowed. ^napp-9x0s *)

val decode :
  spec:'cfg t -> getenv:(string -> string option) -> string -> ('cfg, error) result
(** Parse TOML, convert it to [Yojson.Safe.t], decode with [spec.of_yojson], then apply
    [spec.env]. TOML dates and non-finite floats are refused with the JSON pointer of the
    value; a decode failure is the deriver's message unchanged. *)

val load_with :
  missing:missing ->
  spec:'cfg t ->
  getenv:(string -> string option) ->
  read:(string -> (string, read_error) result) ->
  source:source ->
  ('cfg, error) result
(** Read then decode; [read] is supplied by the Door to allow in-memory tests. A
    [`Default] source that is [`Missing] decodes the empty document — so a config type
    whose fields all carry defaults starts a fresh install with no file — while an
    [`Explicit] source that is [`Missing] is an error naming the path, and an
    [`Unreadable] file is an error naming the path either way. ^napp-9x0s ^napp-ersz:
    [missing = `Required] rejects an absent default as well. *)

val read_regular : max_bytes:int -> _ Eio.Path.t -> (string, read_error) result
(** Read a regular file only, inspecting its opened descriptor and bounding the bytes
    buffered even when the file grows. Missing paths remain [`Missing]; non-regular and
    oversized paths are [`Unreadable]. Reading may suspend or be cancelled. Use as the
    production [read_file] policy when a consumer has a byte limit. ^napp-ersz *)

val load :
  spec:'cfg t ->
  getenv:(string -> string option) ->
  read:(string -> (string, read_error) result) ->
  source:source ->
  ('cfg, error) result
(** Original defaults-on-missing behavior; reading may suspend or be cancelled. *)
