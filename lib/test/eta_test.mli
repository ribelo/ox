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
    Eio's normal rules. *)

val advance : Eio_mock.Clock.t -> Eta.Duration.t -> unit
(** Sets virtual wall time and yields to let due sleepers run; does not run switch
    finalizers. Caller controls the monotonic clock separately. *)

type ('a, 'e) handle

val fork_run : sw:Eio.Switch.t -> (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) handle
(** Starts [Eta.Scope.run] in [sw]. External cancellation is classified by Scope.run and
    cleanup is awaited. *)

val await : ('a, 'e) handle -> ('a, 'e) Eta.Exit.t
(** Waits for the classified Exit; cancellation of the waiter propagates. *)

val with_census : (unit -> 'a) -> int
(** Count still-live Eio fibers created during the call. Events are drained before and
    after the call; pre-existing fibers are excluded. Does not cancel fibers. *)

val assert_no_fibers_left : unit -> unit
(** Fails when any Eio fiber created since the current [run] began is still alive.
    Includes forks outside [fork_run]; excludes the calling root fiber. A lost trace event
    fails closed. Does not cancel fibers or run their finalizers. *)

val cause : 'e Alcotest.testable -> 'e Eta.Cause.t Alcotest.testable

val exit :
  'a Alcotest.testable -> 'e Alcotest.testable -> ('a, 'e) Eta.Exit.t Alcotest.testable
(** Structural comparison ignores backtraces in defects; pure, with no cancellation or
    finalizer effects. *)

val flow_pair : ?label:string -> string list -> Eio_mock.Flow.t * Eio_mock.Flow.t
(** A scripted readable flow (one read per chunk, then EOF) and writable sink. Neither
    registers a finalizer; callers can inspect writes with Eio tracing or configure the
    sink using Eio_mock.Flow. *)

module Process : sig
  type stream = Stdout | Stderr  (** The child's standard output or standard error. *)

  type chunk = { stream : stream; data : string; after : Eta.Duration.t }
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
      without [clock]; the clock is the mock one [advance] moves. *)

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
      argv, env, cwd and fds. *)

  val spawns : t -> spawn list
  (** Spawns in call order; descriptors are retained as opaque references. *)

  val signals : t -> int list
  (** Signals received in call order, including cleanup SIGKILL when pending. *)
end
