# iomux: lost SIGCHLD wakeup between the OCaml blocking-section check and Linux ppoll

Operator filing draft; **not posted**. Covers Ox story [nwake-i8u6](<../issues/posix-wakeup/01-posix-wakeup.md>).

## Symptom and environment

With Eio's posix backend, a short-lived child can exit while its parent remains
blocked indefinitely in iomux's native `ppoll`. The child is already a zombie;
the OCaml SIGCHLD callback has not run, so Eio's exit-status promise remains
unresolved. This occurs with plain Eio, without Pie or Ox.

Observed on Linux/NixOS with OxCaml 5.4.0-ox2 (`ocamlc -version` reports
`5.4.0+ox`), Eio 1.3+ox and iomux 0.4, using `EIO_BACKEND=posix` and one
OCaml domain. We have not established whether every upstream OCaml version has
the same race. Eio's Linux backend uses pidfds for child readiness and does not
rely on this SIGCHLD wakeup path; moving services to it is a separate operational
decision, not part of this proposed iomux repair.

Expected: the immediately exiting child is promptly reaped and the run returns.
Actual: the parent can sleep indefinitely after the child exits, until some
unrelated event makes the scheduler return from `ppoll`.

## Minimal standalone reproducer

Create these three files in a fresh directory with `eio_main` installed; no Pie
or Ox dependency is needed.

`reap.ml`:

```ocaml
(* /bin/sh is used because NixOS has no /bin/true. "exit 0" is equivalent. *)
let () =
  Eio_main.run @@ fun env ->
  let mgr = Eio.Stdenv.process_mgr env in
  for _ = 1 to 1000 do
    Eio.Process.run mgr [ "/bin/sh"; "-c"; "exit 0" ]
  done
```

`dune`:

```lisp
(executable
 (name reap)
 (libraries eio_main))
```

`dune-project`:

```lisp
(lang dune 3.19)
(name eio_reap_hang)
```

On systems with `/bin/true`, that command can replace `/bin/sh -c "exit 0"`.
Build once, then run **separate untraced processes** with external deadlines.
The shell loop continues after timeouts so all 50 attempts are counted:

```sh
dune build reap.exe
passed=0; timed_out=0; other=0
for i in $(seq 1 50); do
  status=0
  timeout --kill-after=1 5 env EIO_BACKEND=posix _build/default/reap.exe || status=$?
  case "$status" in
    0) passed=$((passed + 1)) ;;
    124) timed_out=$((timed_out + 1)) ;;
    *) other=$((other + 1)) ;;
  esac
done
printf 'passed=%s timed_out=%s other=%s\n' "$passed" "$timed_out" "$other"
```

An Eio-fiber timeout alone is not an adequate detector: its own cleanup can wait
for child reaping after that timer has gone away. Use an external process
watchdog. The reproducer spawns 1,000 children per completed run.

## Evidence from the original investigation

The following debugger and syscall excerpts are preserved historical evidence,
not newly collected traces for the Ox workaround.

A naturally stalled parent, PID 2554338, was sleeping in
`poll_schedule_timeout`; fake wtype child PID 2554358 was already a zombie.
GDB was attached from an ancestor process because `ptrace_scope=1` denied
normal sibling attachment:

```text
#2 ppoll()
#4 caml_iomux_ppoll (...) at iomux_stubs.c:89
#6 camlIomux__Poll__ppoll_5_19_code () at lib/poll.ml:83
#7 camlEio_posix__Sched__next_13_54_code ()
(gdb) p caml_pending_signals
$1 = {65536}
```

The runtime stores signal number n in bit n-1. On this Linux system SIGCHLD is
17, so 65536 is its pending bit: the OS signal has been recorded by the native
handler, but the OCaml callback has not executed.

Another stalled run, parent PID 2538926, was attached with strace **after** the
stall. Its only live descriptor in the poll set was Eio's wakeup fd 6:

```text
2538926 17:38:07.185935 ppoll([{fd=-1}, {fd=-1}, {fd=-1}, {fd=-1}, {fd=-1}, {fd=-1}, {fd=6, events=POLLIN}], 7, NULL, NULL, 8 <detached ...>
```

Both the timeout and signal-mask arguments were NULL. stdout/stderr and the
exec-error pipes had already been drained/removed. This is not a child blocked
on stdin, output backpressure, or an await-before-drain deadlock. Eio_posix's
`Process.await` awaits an exit-status promise; its low-level reaper calls
`waitpid(WNOHANG)` when notified via `Eio_unix.Process.sigchld`. There was one
reaper per child, not two competing waitpid owners. Pie's `Sh.run` calls
`Eio.Process.run` directly, so changing Ox_process alone would not cover it.

Tracing from startup perturbed the timing: forty such strace runs passed while
untraced executions hung. A passing traced run does not disprove the race.

## Root cause

The iomux 0.4 primitive calls `caml_enter_blocking_section()`, then
`ppoll(..., NULL)` for this case. The tested OxCaml runtime checks pending
signals before releasing the runtime lock. The lost-wakeup window is:

1. The runtime performs its pending-signal check.
2. SIGCHLD arrives before the kernel `ppoll` starts. Its native handler records
   the signal, but the OCaml callback is deferred.
3. The primitive enters an infinite `ppoll`. Since delivery already happened,
   that signal does not interrupt the not-yet-started syscall.
4. The deferred OCaml callback would broadcast the SIGCHLD condition and wake
   the scheduler, but cannot execute until `ppoll` returns. With no other
   readiness or timer, the finished child is never reaped.

`ppoll` can atomically replace the calling thread's signal mask while sleeping,
but an unmasked runtime-check-to-syscall gap defeats that protection.

## Experimental cause-level repair

Proposed direction: block signal delivery on the polling thread before entering
the blocking section; do not execute OCaml callbacks under that temporary mask;
return EINTR if the runtime already has a recorded signal; otherwise let
`ppoll` atomically install the requested/original mask for the wait. Restore
the original mask and errno before re-entering OCaml.

These are the **experimental changes against iomux 0.4**, not a reviewed
production patch. Only unchanged context has been omitted from the preserved
patch (apply this form with `git apply --unidiff-zero`):

```diff
--- a/lib/iomux_stubs.c
+++ b/lib/iomux_stubs.c
@@ -4,0 +5,1 @@
+#include <pthread.h>
@@ -16,0 +18,2 @@
+/* Diagnostic repair for OCaml 5: this is a runtime-internal API. */
+CAMLextern int caml_check_pending_signals (void);
@@ -88,2 +91,24 @@
-	caml_enter_blocking_section();
-	r = ppoll(fds, nfds, timo, psigmask);
+	/* Close the gap between the runtime pending-signal check and ppoll.
+	 * A signal delivered in that gap otherwise remains pending in OCaml
+	 * while ppoll sleeps forever. Block delivery here, then atomically
+	 * restore the requested mask in ppoll. Already-recorded signals must
+	 * return to OCaml rather than enter a blocking syscall. */
+	sigset_t all_signals, oldmask;
+	sigfillset(&all_signals);
+	int mask_error = pthread_sigmask(SIG_BLOCK, &all_signals, &oldmask);
+	if (mask_error != 0) {
+		errno = mask_error;
+		uerror("pthread_sigmask", Nothing);
+	}
+	/* No OCaml callbacks may raise while the temporary mask is installed. */
+	caml_enter_blocking_section_no_pending();
+	if (caml_check_pending_signals()) {
+		r = -1;
+		errno = EINTR;
+	} else {
+		r = ppoll(fds, nfds, timo, psigmask ? psigmask : &oldmask);
+	}
+	int saved_errno = errno;
+	mask_error = pthread_sigmask(SIG_SETMASK, &oldmask, NULL);
+	errno = mask_error != 0 ? mask_error : saved_errno;
+	if (mask_error != 0) r = -1;
```

### Exact limits and review needed

- **Internal runtime API:** `caml_check_pending_signals` is not a stable public
  OCaml API. Compatibility and safe use of it, together with
  `caml_enter_blocking_section_no_pending`, need runtime-maintainer review.
- **Linux ppoll only:** only the native Linux ppoll path and native linking
  were exercised. The fallback poll implementation and other platforms are not
  repaired or validated by this experiment.
- **Single domain only; not multidomain-reviewed:** blocking delivery on this
  thread closes the observed window, not every runtime-wide signal race. A
  signal recorded on another thread between the pending check and poll still
  needs a runtime-wide wake mechanism.
- Explicit caller masks, already-masked signals, signal delivery across
  domains, runtime versions, mask-restoration/error paths and fallback-poll
  behavior need dedicated tests and review before release.

The experiment did not install or vendor a production dependency. Dune refused
a source-vendored iomux because installed eio_posix referred to the installed
library. The investigator instead linked a local C-only wrapper using GNU ld
`--wrap=caml_iomux_ppoll`, exercising the same changed primitive. A fixed
trace showed block → ppoll with an explicit empty mask → restore:

```text
rt_sigprocmask(SIG_BLOCK, ~[RTMIN RT_1], [], 8) = 0
ppoll([{fd=-1}, {fd=-1}, {fd=-1}, {fd=3, events=POLLIN}], 4, NULL, [], 8) = ? ERESTARTNOHAND (To be restarted if no handler)
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=2726443, si_uid=1000, si_status=0, si_utime=0, si_stime=0} ---
rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
```

### Measurements and evidence limits

Original research, before any Ox ticker:

| Case | Native primitive | Passed | Timed out | Other failures | External deadline/run |
| --- | --- | ---: | ---: | ---: | ---: |
| Plain Eio, 1,000 children | Installed | 28/50 | 22/50 | 0 | 2 s |
| Plain Eio, 1,000 children | Experimental wrapper | 50/50 | 0/50 | 0 | 5 s |
| Pie prepared-text, master 489f473 | Installed | 37/50 | 13/50 | 0 | 2 s |
| Pie prepared-text, master 489f473 | Experimental wrapper | 50/50 | 0/50 | 0 | 5 s |

The successful standalone experiment completed 50,000 child processes. These
are empirical results, not a proof of portability or multidomain correctness;
the different external deadlines must not be hidden in comparisons.

A fresh **installed-old-Ox baseline** for row 55 on 2026-09-29, Pie master
`c1cdcc1f80bf353b08904c6b090e2c30ffce10ef`, completed 29/50 prepared-text
runs and timed out 21/50 (status 124), with zero other failures. Each run used
`EIO_BACKEND=posix` and `timeout --kill-after=1 5`; the test executable was
built in `_build_r55` against the shared installed packages, without the
experimental native wrapper or new Ox mitigation. Installed ox_app's metadata
version was `v1-boundary-118-gb6d8629-dirty`. Successful runs completed all
21 tests; a sampled timeout stopped partway through helper invocations.
This new baseline is **not** a successful test of the ticker.

Failure frequency changes with load and timing. An earlier original-research
prepared-text sample passed 49/50; that did not imply reliability.

## Ox workaround: 50 ms posix wake-up ticker

Ox's row-55 mitigation is a periodic Eio clock fiber around Door program
execution on the actual posix backend (`Eio.Stdenv.backend_id`, including
automatic fallback). Runtime-owning callers outside the Door can install the
same fiber with `Ox_app.posix_wakeup`. The runtime-free `with_powerbox` does not
start Eio or a ticker; its synchronous grip consumer spawns no Eio children.
It sleeps **50 ms**
by default, configurable with `0` disabling it; no ticker is needed on the
Linux backend. Only service-program startup logs the chosen backend and interval
(e.g. `backend=posix wakeup_ms=50`) through the filtered Door journal logger;
`?journal_level` still governs it, and it does not add a telemetry record.
Owned/client/config commands start the ticker silently and preserve empty stderr.
The public helper is silent unless given an explicit logger.

Keeping an outstanding timer makes the scheduler's wait finite. A missed
SIGCHLD wakeup is then handled on a subsequent tick rather than waiting forever.
The intended extra race-hit latency is roughly one interval, subject to normal
scheduling; it is not a hard real-time guarantee. A process-wide 50 ms ticker
costs about 20 scheduler wakeups per second even when idle. The historical
research preferred a ticker scoped to each outstanding child operation; row 55
instead chooses one at the shared Door boundary to cover direct Eio subprocess
call sites consistently. This is a mitigation,
not a fix to the native signal boundary; it should be removed when the
underlying dependency is repaired or the service moves to a pidfd backend.

**The ticker must outlive protected child cleanup.** It has to stay armed from
before spawn through pipe draining, awaiting and final process-switch teardown,
including cancellation and exceptions. A daemon sharing the program's
cancelling switch, or `Fiber.first(run, ticker)`, may be cancelled before
`Eio.Process` performs its cancellation-protected kill/await cleanup. That
can leave the same indefinite wait during shutdown. Its lifetime/cancellation
protection must encompass the full program/process scope exit. Ox owns the
daemon on an outer switch around signal handling and inner program switches,
so it is cancelled promptly only after those scopes and their cleanup return.
The daemon itself cannot keep the outer switch alive.

Do not replace Eio's SIGCHLD handler, introduce another waitpid owner, or use
blocking Unix.sleep. The native patch above is not being installed as the Ox
workaround. New-Ox consumer verification is separate from the historical wrapper:
Pie prepared-text now passes **50/50**, with zero timeouts or other failures,
using the same 5-second OS bound against private `/tmp/ox-r55/lib` and a test-only
`Pie_test_runtime.run` that explicitly owns the outer-switch ticker. The shared
helper replaces 94 direct runtime sites in eleven child-owning test harnesses;
the full posix Pie suite, formatting and caps gates also pass. Installing a new
Door library alone cannot mitigate a direct-Eio test runtime that bypasses it.

For the new 50 × 1,000-child Ox populations, the unchanged plain-Eio control
passes **47/50** and times out **3/50**, while the Door with the 50 ms tick passes
**50/50**. Crucially, the Door with the tick disabled also passes **50/50**,
including sequential and bounded CPU-contention runs. The Door's changed
topology can affect the race timing; its passing disabled population is not
proof of a fixed dependency and the cause of that timing difference is unknown.
The untraced control timeouts supply the current failing evidence, and the
prepared-text **29/50 → 50/50** comparison supplies the consumer mitigation
evidence. Full conditions are in [Ox stress evidence](<../../test/stress-posix-wakeup/README.md>).

## Short note for Eio maintainers

The standalone program uses only `Eio.Process.run` under `EIO_BACKEND=posix`.
Its exit-status promise can remain unresolved while SIGCHLD is pending in the
OCaml runtime and iomux sleeps indefinitely. Please coordinate with iomux and
runtime maintainers on an atomic signal-check/wait boundary or a runtime-wide
wake mechanism, rather than adding a competing child reaper. In particular,
regression coverage should include cancellation-protected process cleanup after
ordinary timer fibers have been cancelled. The Linux pidfd process backend is
an alternative path; the supplied experimental patch is Linux/single-domain
only and not ready for general dependency release.

## Local provenance for the operator

The preserved [research report](<../../../../pie/docs/research/2026-09-29-sigchld-ppoll-race/REPORT.md>),
[standalone source](<../../../../pie/docs/research/2026-09-29-sigchld-ppoll-race/repro/reap.ml>),
[experimental patch](<../../../../pie/docs/research/2026-09-29-sigchld-ppoll-race/iomux-ppoll-experiment.patch>),
[hung trace](<../../../../pie/docs/research/2026-09-29-sigchld-ppoll-race/hung-strace.log>)
and [fixed trace](<../../../../pie/docs/research/2026-09-29-sigchld-ppoll-race/fixed-strace.log>)
are sibling-repository evidence. The inline reproducer, patch and excerpts above
make the issue self-contained when copied to an upstream tracker. No upstream
issue has been submitted by the agent.
