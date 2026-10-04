(** The dangerous [Sys] calls, each requiring its capability (^ncaps-4btv). Same contract
    as {!Cap_unix}: the raw call and nothing else, the capability only looked at, and
    calls may block the domain; the wrappers add no Eio check. Keep blocking calls out of
    [Ox.Actor] handlers and [Ox.Agent] closures. ^nlintd-a7oq *)

(** Cancellation and finalizers: Suspension: never suspends in the wrapper; underlying
    calls are delegated to Stdlib.Sys and may block the domain. Cancellation: not a
    cancellation point in the wrapper; underlying checks and callbacks are delegated to
    Stdlib.Sys, with no additional Eio cancellation check. Finalizers: no Eio switch
    finalizer is registered; returned open handles are caller-owned. Locking: the wrapper
    acquires no lock of its own; delegated runtime locking is unchanged. ^nlintd-von6
    ^nlintd-a7oq *)

val command : caps:< Cap.fork ; Cap.exec ; .. > -> string -> int
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

(** Finalizers: Stdlib.In_channel.with_open_bin closes the private /dev/urandom channel on
    return or exception; no switch hook is registered. ^nlintd-a7oq *)

val urandom : caps:< Cap.random ; Cap.fs_read ; .. > -> int -> string
(** [urandom ~caps n] reads [n] bytes from [/dev/urandom]: unpredictable bytes for a
    handle or a token. Raises [Sys_error] when the device cannot be read and [End_of_file]
    if it returns fewer bytes. Requires [Cap.fs_read] as well as [Cap.random] because the
    implementation reads the device through a channel. A [getrandom(2)] binding would
    remove the filesystem-read requirement. *)
