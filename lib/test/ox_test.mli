type env =
  < clock : Eio_mock.Clock.t
  ; mono_clock : Eio_mock.Clock.Mono.t
  ; fs : Eio.Fs.dir_ty Eio.Path.t
  ; cwd : Eio.Fs.dir_ty Eio.Path.t
  ; net : [ `Unix | `Generic ] Eio.Net.ty Eio.Resource.t
  ; process_mgr : Eio_unix.Process.mgr_ty Eio.Resource.t
  ; backend_id : string >
(** Test helpers over Eio and Eio_mock. [run] owns its Eio_main loop and switch; switch
    cleanup waits for children and finalizers. *)

val run : (env -> Eio.Switch.t -> 'a) -> 'a
(** Runs with manually controlled mock wall and monotonic clocks, with the actual stdenv's
    fs, cwd, net and process manager. The operating system is NOT virtualized. Switch
    finalizers and children finish before return; cancellation propagates according to
    Eio's normal rules. Suspension: may suspend in the caller callback and Eio switch
    join. Cancellation: propagates Eio.Cancel.Cancelled from caller code and Eio waits.
    Finalizers: the owned switch joins children and runs its release hooks protected
    before Eio_main returns. Locking: no harness lock spans the callback. Cancellation
    safety: unsafe because progress is lost; completed callback effects and mock clock
    updates remain if the run is interrupted. Failures from caller code, owned children
    and release hooks are delegated to Eio.Switch.run and re-delivered at the join; their
    exception constructors depend on that code. ^nlintd-a7oq ^nlintd-truth ^nlintd-raises
*)

val advance : Eio_mock.Clock.t -> Ox.Duration.t -> unit
(** Sets virtual wall time and yields to let due sleepers run; does not run switch
    finalizers. Caller controls the monotonic clock separately. Suspension: may suspend at
    Eio.Fiber.yield after setting the mock wall clock. Cancellation: propagates
    Eio.Cancel.Cancelled from that yield. Finalizers: none are registered. Locking: no
    lock is acquired. Cancellation safety: unsafe because progress is lost; the clock
    update is already committed before the yield. ^nlintd-a7oq *)

type ('a, 'e) handle

val fork_run : sw:Eio.Switch.t -> (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) handle
(** Starts [Ox.Scope.run] in [sw]. External cancellation is classified by Scope.run and
    cleanup is awaited. Suspension: may suspend while Eio starts the fiber and in the
    caller callback. Cancellation: propagates Eio.Cancel.Cancelled from fork startup; the
    child Scope.run classifies its interruption. Finalizers: the child scope joins its
    fibers and runs its protected release hooks before settling the promise. Locking: no
    harness lock spans caller code. Cancellation safety: unsafe because progress is lost;
    child callback effects can begin before fork_run returns. ^nlintd-a7oq

    A finished sw causes Invalid_argument in the delegated Eio fork. *)

val await : ('a, 'e) handle -> ('a, 'e) Ox.Exit.t
(** Waits for the classified Exit; cancellation of the waiter propagates. *)

val with_census : (unit -> 'a) -> int
(** Count still-live Eio fibers created during the call. Events are drained before and
    after the call; pre-existing fibers are excluded. Does not cancel fibers.

    The census starts the process's runtime_events ring when this library is loaded and
    keeps that ring in a private temporary directory: the runtime fixes the ring's
    directory before any OCaml code runs, so the census reaches the only lever left in the
    process and creates the ring by turning the working directory into its temporary one
    for the calls that name the ring by path, restoring it at once. The directory is
    removed when the process exits, so a process killed before its exit handlers run
    (SIGKILL) leaves its [<pid>.events] ring in that temporary directory and nowhere else.
    Where [OCAML_RUNTIME_EVENTS_DIR] is already set in the environment, the launcher has
    chosen the directory and the census leaves the ring there. *)

val assert_no_fibers_left : unit -> unit
(** Fails when any Eio fiber created since the current [run] began is still alive.
    Includes forks outside [fork_run]; excludes the calling root fiber. A lost trace event
    fails closed, but only one lost since the current [run] began: a heavy earlier test
    that never took a census cannot fail a later one. Does not cancel fibers or run their
    finalizers. The ring placement that {!with_census} documents applies to the whole
    census. *)

val cause : 'e Alcotest.testable -> 'e Ox.Cause.t Alcotest.testable

val exit :
  'a Alcotest.testable -> 'e Alcotest.testable -> ('a, 'e) Ox.Exit.t Alcotest.testable
(** Structural comparison ignores backtraces in defects; pure, with no cancellation or
    finalizer effects. *)

val powerbox : unit -> Ox_caps.Cap.all_caps
(** The test entry's powerbox (^ncaps-0mvw): what a test hands a function whose signature
    requires capabilities, the way the Door hands [Ox_app.Env.caps] to a program. Tests
    are outside the capability gate; library code that calls this is refused by the
    [ox-caps-mint] rule. Pure; no resource.

    Suspension: never suspends; this call only constructs or reads OCaml values and
    captures dependencies without invoking them. Cancellation: not a cancellation point;
    this call performs no Eio cancellation check. Finalizers: this call registers no
    switch hook and leaves captured resources with their existing owner. Locking: this
    call acquires no lock; construction of synchronization objects does not acquire them.
    ^nlintd-a7oq *)

val flow_pair : ?label:string -> string list -> Eio_mock.Flow.t * Eio_mock.Flow.t
(** A scripted readable flow (one read per chunk, then EOF) and writable sink. Neither
    registers a finalizer; callers can inspect writes with Eio tracing or configure the
    sink using Eio_mock.Flow. Suspension: never suspends; mock flow construction is
    delegated to Eio_mock and installs no I/O action; delegated Stdlib, Stdlib.List
    operations retain their own behaviour. Cancellation: not a cancellation point;
    construction is delegated to Eio_mock without an Eio check; delegated Stdlib,
    Stdlib.List operations retain their own behaviour. Finalizers: none are registered.
    Locking: no lock is acquired. ^nlintd-a7oq *)

module Process : sig
  type stream = Stdout | Stderr  (** The child's standard output or standard error. *)

  type chunk = { stream : stream; data : string; after : Ox.Duration.t }
  (** One write to [stream], delivered [after] the spawn or the preceding chunk on the
      script's clock; a zero [after] writes without waiting. *)

  type script =
    | Exit of Eio.Process.exit_status
    | Block_until_signal
    | Output of chunk list * script
        (** What one spawn does: [Exit status] ends at once, [Block_until_signal] waits
            for a signal, and [Output (chunks, rest)] writes [chunks] in order and then
            behaves as [rest]. *)

  type spawn = {
    argv : string list;
    env : string array;
    cwd : Eio.Fs.dir_ty Eio.Path.t option;
    pgid : int option;
    executable : string;
    fds : (int * Eio_unix.Fd.t * Eio_unix.Private.Fork_action.blocking) list;
  }

  type t

  val make : ?clock:_ Eio.Time.clock -> script list -> t
  (** Each spawn consumes one script. Exhaustion is a test defect, as is a chunk delayed
      without [clock]; the clock is the mock one [advance] moves.

      Suspension: never suspends; this call only constructs or reads OCaml values and
      captures dependencies without invoking them; delegated Ox.Duration, Stdlib.List,
      Stdlib.Option operations retain their own behaviour. Cancellation: not a
      cancellation point; this call performs no Eio cancellation check; delegated
      Ox.Duration, Stdlib.List, Stdlib.Option operations retain their own behaviour.
      Finalizers: this call registers no switch hook and leaves captured resources with
      their existing owner. Locking: this call acquires no lock; construction of
      synchronization objects does not acquire them. ^nlintd-a7oq

      @raise Invalid_argument
        if a chunk has a nonzero delay and clock is absent. ^nlintd-raises *)

  val mgr : t -> Eio_unix.Process.mgr_ty Eio.Resource.t
  (** Real Eio process-manager resource supporting both [spawn] and [spawn_unix]. Pipes
      use Eio's Unix backend, but no child OS process is started. Generic spawns accept
      FD-backed standard streams only and do not check whether the executable exists. [sw]
      cleanup sends SIGKILL to a blocked child.

      A script's chunks are written to the descriptors the spawn maps to child fds 1 and
      2, so a [Pipe] child is read exactly as a real one. A daemon of the spawn's switch
      writes them in script order; it ends after the last chunk of an [Exit] script and
      when the child is signalled or retired, and its last act is to close the write ends,
      so a reader sees the bytes written so far followed by EOF. A chunk whose delay had
      not elapsed when the child was signalled is not written. The fake still records
      argv, env, cwd and fds.

      Suspension: never suspends; this call only constructs or reads OCaml values and
      captures dependencies without invoking them; delegated Eio_unix.Process operations
      retain their own behaviour. Cancellation: not a cancellation point; this call
      performs no Eio cancellation check; delegated Eio_unix.Process operations retain
      their own behaviour. Finalizers: this call registers no switch hook and leaves
      captured resources with their existing owner. Locking: this call acquires no lock;
      construction of synchronization objects does not acquire them. ^nlintd-a7oq *)

  val spawns : t -> spawn list
  (** Spawns in call order; descriptors are retained as opaque references.

      Suspension: never suspends; this call only constructs or reads OCaml values and
      captures dependencies without invoking them; delegated Stdlib.List operations retain
      their own behaviour. Cancellation: not a cancellation point; this call performs no
      Eio cancellation check; delegated Stdlib.List operations retain their own behaviour.
      Finalizers: this call registers no switch hook and leaves captured resources with
      their existing owner. Locking: this call acquires no lock; construction of
      synchronization objects does not acquire them. ^nlintd-a7oq *)

  val signals : t -> int list
  (** Signals received in call order, including cleanup SIGKILL when pending. *)
end
