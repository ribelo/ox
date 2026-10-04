(** The dangerous [Unix] calls, each requiring its capability (^ncaps-4btv). The
    Compiler-backed [ox-caps-*] rules forbid the raw [Unix] functions outside this
    library; each function here is the raw call with the capability in front of it and
    nothing else; the capability is only looked at, never kept. It is an ordinary (global)
    argument so that a partial application such as [~getenv:(Cap_sys.getenv_opt ~caps)] is
    an ordinary closure, and a [@ local] closure — the thunk of [Ox.Rate_limiter.run], the
    acquire of [Ox.Resource.use_in_scope] — can capture a capability and call these.

    The synchronous wrapper adds no Eio operation or cancellation check; its direct calls
    may block the domain. Code you hand it remains yours: [establish_server] calls an
    arbitrary callback that can suspend and observe cancellation. ^nlintd-a7oq Do not make
    blocking calls from an [Ox.Actor] handler or an [Ox.Agent] closure, which run
    cancel-protected in the owner fiber and must not block for long; spawn children
    through Eio's [process_mgr] ([Ox_process.Child.spawn]) instead of [fork]/[exec], and
    run a blocking call through [Ox_blocking]. *)

(** Cancellation and finalizers: Suspension: never suspends in Eio; these direct calls may
    block the domain. Cancellation: not a cancellation point; the wrapper performs no Eio
    cancellation check. Finalizers: no Eio switch finalizer is registered; returned open
    handles are caller-owned. Locking: the wrapper acquires no lock of its own; delegated
    runtime locking is unchanged. ^nlintd-von6 ^nlintd-a7oq *)

(** {1 fork, exec} *)

val fork : caps:< Cap.fork ; .. > -> unit -> int
val execv : caps:< Cap.exec ; .. > -> string -> string array -> 'a
val execve : caps:< Cap.exec ; .. > -> string -> string array -> string array -> 'a
val execvp : caps:< Cap.exec ; .. > -> string -> string array -> 'a
val execvpe : caps:< Cap.exec ; .. > -> string -> string array -> string array -> 'a

val create_process :
  caps:< Cap.exec ; .. > ->
  string ->
  string array ->
  Unix.file_descr ->
  Unix.file_descr ->
  Unix.file_descr ->
  int

val create_process_env :
  caps:< Cap.exec ; .. > ->
  string ->
  string array ->
  string array ->
  Unix.file_descr ->
  Unix.file_descr ->
  Unix.file_descr ->
  int

val open_process_in : caps:< Cap.exec ; .. > -> string -> in_channel
val open_process_out : caps:< Cap.exec ; .. > -> string -> out_channel
val open_process : caps:< Cap.exec ; .. > -> string -> in_channel * out_channel

val open_process_full :
  caps:< Cap.exec ; .. > ->
  string ->
  string array ->
  in_channel * out_channel * in_channel

val open_process_args_in : caps:< Cap.exec ; .. > -> string -> string array -> in_channel

val open_process_args_out :
  caps:< Cap.exec ; .. > -> string -> string array -> out_channel

val open_process_args :
  caps:< Cap.exec ; .. > -> string -> string array -> in_channel * out_channel

val system : caps:< Cap.exec ; .. > -> string -> Unix.process_status

(** {1 exit, chdir, environment, signals, time} *)

val _exit : caps:< Cap.exit ; .. > -> int -> 'a
val chdir : caps:< Cap.chdir ; .. > -> string -> unit
val getenv : caps:< Cap.env ; .. > -> string -> string
val environment : caps:< Cap.env ; .. > -> unit -> string array

val putenv : caps:< Cap.env ; .. > -> string -> string -> unit
[@@alert
  unsafe_multidomain "Mutating the environment makes reading the environment unsafe."]

val kill : caps:< Cap.signal ; .. > -> int -> int -> unit

val sigprocmask :
  caps:< Cap.signal ; .. > -> Unix.sigprocmask_command -> int list -> int list

val time : caps:< Cap.time ; .. > -> unit -> float
val gettimeofday : caps:< Cap.time ; .. > -> unit -> float

(** {1 Filesystem} *)

val openfile :
  caps:< Cap.fs_read ; Cap.fs_write ; .. > ->
  string ->
  Unix.open_flag list ->
  Unix.file_perm ->
  Unix.file_descr
(** Both capabilities: the flags decide at run time whether the descriptor reads, writes
    or creates. *)

val openfile_write :
  caps:< Cap.fs_write ; .. > ->
  string ->
  Unix.open_flag list ->
  Unix.file_perm ->
  Unix.file_descr
(** Open a write-only descriptor. Reject [O_RDONLY] and [O_RDWR] flags; the wrapper
    supplies [O_WRONLY]. A lockfile used only for [lockf] and [fstat] needs no read
    access. *)

val open_dev_null : unit -> Unix.file_descr
(** A write-only, close-on-exec descriptor on [/dev/null]. No capability: the null device
    neither reads nor keeps anything, and discarding a child's output is part of spawning
    it. *)

val opendir : caps:< Cap.fs_read ; .. > -> string -> Unix.dir_handle
val unlink : caps:< Cap.fs_write ; .. > -> string -> unit
val rename : caps:< Cap.fs_write ; .. > -> string -> string -> unit
val mkdir : caps:< Cap.fs_write ; .. > -> string -> Unix.file_perm -> unit
val rmdir : caps:< Cap.fs_write ; .. > -> string -> unit
val chmod : caps:< Cap.fs_write ; .. > -> string -> Unix.file_perm -> unit
val truncate : caps:< Cap.fs_write ; .. > -> string -> int -> unit
val symlink : caps:< Cap.fs_write ; .. > -> ?to_dir:bool -> string -> string -> unit
val link : caps:< Cap.fs_write ; .. > -> ?follow:bool -> string -> string -> unit

(** {1 Network} *)

val socket :
  caps:< Cap.network ; .. > ->
  ?cloexec:bool ->
  Unix.socket_domain ->
  Unix.socket_type ->
  int ->
  Unix.file_descr

val open_connection :
  caps:< Cap.network ; .. > -> Unix.sockaddr -> in_channel * out_channel

val establish_server :
  caps:< Cap.network ; Cap.fork ; .. > ->
  (in_channel -> out_channel -> unit) ->
  Unix.sockaddr ->
  unit
(** Forks a child per connection, hence [fork] as well.

    Suspension: may suspend in the supplied server callback; Unix socket operations may
    block the domain. Cancellation: depends on the callback; the wrapper adds no Eio
    protection. Finalizers: server process and socket cleanup are delegated to
    Unix.establish_server, not an Eio switch. Locking: socket and process locking are
    delegated to Unix. ^nlintd-a7oq *)
