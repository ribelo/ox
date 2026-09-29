(** The dangerous [Sys] calls, each requiring its capability (^ncaps-4btv). Same contract
    as {!Cap_unix}: the raw call and nothing else, the capability only looked at, and
    every call blocks the domain without observing cancellation — keep them out of
    [Ox.Actor] handlers and [Ox.Agent] closures. *)

val command : caps:< Cap.exec ; .. > -> string -> int
val chdir : caps:< Cap.chdir ; .. > -> string -> unit
val getenv : caps:< Cap.env ; .. > -> string -> string
val getenv_opt : caps:< Cap.env ; .. > -> string -> string option

val signal : caps:< Cap.signal ; .. > -> int -> Sys.signal_behavior -> Sys.signal_behavior
[@@alert
  unsafe_multidomain
    "Sys.signal installs a handler for every domain; see Sys.Safe.signal."]

val set_signal : caps:< Cap.signal ; .. > -> int -> Sys.signal_behavior -> unit
[@@alert
  unsafe_multidomain
    "Sys.set_signal installs a handler for every domain; see Sys.Safe.set_signal."]

val time : caps:< Cap.time ; .. > -> unit -> float
val readdir : caps:< Cap.fs_read ; .. > -> string -> string array
val remove : caps:< Cap.fs_write ; .. > -> string -> unit
val rename : caps:< Cap.fs_write ; .. > -> string -> string -> unit
val mkdir : caps:< Cap.fs_write ; .. > -> string -> int -> unit
val rmdir : caps:< Cap.fs_write ; .. > -> string -> unit

val urandom : caps:< Cap.random ; .. > -> int -> string
(** [urandom ~caps n] reads [n] bytes from [/dev/urandom]: unpredictable bytes for a
    handle or a token. Raises [Sys_error] when the device cannot be read and [End_of_file]
    if it returns fewer bytes. *)
