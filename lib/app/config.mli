(** Config loading and schema validation. Reading may suspend or be cancelled;
    decoding is pure, and neither operation registers a finalizer. *)
type error = [ `Config of string ]
val path : name:string -> config:string option -> getenv:(string -> string option) -> string
(** Resolve --config or XDG_CONFIG_HOME, falling back to HOME/.config. *)
val decode : schema:'a Eta_schema.t -> getenv:(string -> string option) -> string -> ('a, error) result
(** Parse TOML, apply schema-declared environment overrides, then validate.
    All decode issues, including unknown keys in closed schemas, retain JSON pointers. *)
val load : schema:'a Eta_schema.t -> getenv:(string -> string option) -> read:(string -> (string, string) result) -> path:string -> ('a, error) result
(** Read then decode; [read] is supplied by the Door to allow in-memory tests. *)
