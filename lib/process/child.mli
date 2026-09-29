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
    cancellation and finalization; both retire. *)

val stdout : t -> Eio.Flow.source_ty Eio.Resource.t option

val stderr : t -> Eio.Flow.source_ty Eio.Resource.t option
(** Parent read ends belong to [spawn]'s owner switch and remain readable after retirement
    until that switch closes. At retirement the child and write ends close, so readers see
    buffered bytes then EOF; unread output cannot block retirement. *)

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
