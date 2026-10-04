(** A Unix child whose private switch survives cancellation of its owning scope. A
    protected daemon owns that switch; a second daemon notices owner cancellation and
    requests retirement. Retirement runs under [Eio.Cancel.protect]: SIGTERM, bounded
    grace, SIGKILL if necessary, reaping, then private-switch release. Thus Eio's own
    SIGKILL-on-release is only a backstop after reaping. [stop] joins concurrent
    retirement; [await] never takes ownership. *)

type exit = Exited of int | Signaled of int
type error = [ `Invalid_fd of int | `Duplicate_fd of int ]
type output = Pipe | Discard
type t

val spawn :
  caps:< Ox_caps.Cap.fork ; Ox_caps.Cap.exec ; Ox_caps.Cap.fs_write ; .. > ->
  sw:Eio.Switch.t ->
  clock:_ Eio.Time.clock ->
  mgr:_ Eio_unix.Process.mgr ->
  argv:string list ->
  ?env:string array ->
  ?cwd:Eio.Fs.dir_ty Eio.Path.t ->
  ?stdout:output ->
  ?stderr:output ->
  grace:Ox.Duration.t ->
  fds:(int * Eio_unix.Fd.t) list ->
  unit ->
  (t, error) result
(** FD mappings borrow the supplied descriptors for spawn, never closing them. Targets 0-2
    and duplicates are rejected before any resource is created. Missing argv and OS launch
    failures are defects, classified at a scope. [Pipe] exposes a source until owner
    switch release; [Discard] routes to /dev/null. Spawn registers switch-owned
    cancellation and finalization; both retire.

    [caps] is what spawning a child may touch (^ncaps-x7z8): it forks and execs another
    program and opens [/dev/null] for writing when output is discarded. Eio's [mgr] spawns
    the process; [fs_write] authorizes opening the null device. A service that launches a
    program shows [< Cap.fork; Cap.exec; Cap.fs_write; .. >] in its own type.

    Suspension: may suspend in Eio fork startup, process-provider operations and awaiting
    the ready promise; delegated Eio_unix, Eio_unix.Fd, Eio_unix.Process, Ox.Duration,
    Ox.Timeout, Ox_caps.Cap_unix, Stdlib, Stdlib.List, Stdlib.Option operations retain
    their own behaviour. Cancellation: propagates Eio.Cancel.Cancelled from startup and
    waits; the cancellation bridge requests protected retirement; delegated Eio_unix,
    Eio_unix.Fd, Eio_unix.Process, Ox.Duration, Ox.Timeout, Ox_caps.Cap_unix, Stdlib,
    Stdlib.List, Stdlib.Option operations retain their own behaviour. Finalizers: owner
    switch release retires the child; the private switch closes its process and
    descriptors after retirement, including on launch failure. Locking: no wrapper lock is
    held; process and FD behavior depends on the Eio Unix provider. Cancellation safety:
    unsafe because progress is lost; the child may execute before startup is interrupted,
    even though retirement closes local resources. ^nlintd-a7oq

    @raise Invalid_argument
      if [sw] is finished or the provider rejects [argv]. A returned Eio Unix pipe without
      a file descriptor causes Failure.

    If a release callback fails while the private child switch closes,
    Eio.Switch.Release_error wraps that cleanup failure and propagates. ^nlintd-raises *)

val pid : t -> int
(** [pid t] is the child's operating-system process id, for status reports and
    diagnostics. Signal it through {!signal}, not with the raw id. ^daily-c4cl *)

val stdout : t -> Eio.Flow.source_ty Eio.Resource.t option
(** Suspension: never suspends; this call only reads or constructs OCaml values.
    Cancellation: not a cancellation point; this call performs no Eio cancellation check.
    Finalizers: none are registered by this call; existing resource ownership is
    unchanged. Locking: no lock is acquired by this call. ^nlintd-a7oq *)

val stderr : t -> Eio.Flow.source_ty Eio.Resource.t option
(** Parent read ends belong to [spawn]'s owner switch and remain readable after retirement
    until that switch closes. At retirement the child and write ends close, so readers see
    buffered bytes then EOF; unread output cannot block retirement. Suspension: never
    suspends; this call only reads or constructs OCaml values. Cancellation: not a
    cancellation point; this call performs no Eio cancellation check. Finalizers: none are
    registered by this call; existing resource ownership is unchanged. Locking: no lock is
    acquired by this call. ^nlintd-a7oq *)

val await : t -> exit
(** Wait for exit, repeatably; waiter cancellation does not terminate the child. No
    finalizer runs simply by awaiting. *)

val signal : t -> int -> unit
(** Signal through Eio's process handle (never a stored PID); no-op once [await] or [stop]
    has reaped the child. The Eio backend protects against PID reuse if the child exits
    before either is called. *)

val stop : t -> exit
(** Terminate and reap, or return the retained exit; repeatable and safe under
    cancellation. Joins the private switch's finalizers before returning. *)
