(** The dangerous [Unix] calls, each requiring its capability (^ncaps-4btv). The
    [ox-caps-*] Semgrep rules forbid the raw [Unix] functions outside this library; each
    function here is the raw call with the capability in front of it and nothing else; the
    capability is only looked at, never kept. It is an ordinary (global) argument so that
    a partial application such as [~getenv:(Cap_sys.getenv_opt ~caps)] is an ordinary
    closure, and a [@ local] closure — the thunk of [Ox.Rate_limiter.run], the acquire of
    [Ox.Resource.use_in_scope] — can capture a capability and call these.

    These calls block the domain; none of them is an Eio suspension point and none
    observes cancellation. Do not call them from an [Ox.Actor] handler or an [Ox.Agent]
    closure, which run cancel-protected in the owner fiber and must not block for long;
    spawn children through Eio's [process_mgr] ([Ox_process.Child.spawn]) instead of
    [fork]/[exec], and run a blocking call through [Ox_blocking]. *)

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
(** Forks a child per connection, hence [fork] as well. *)
