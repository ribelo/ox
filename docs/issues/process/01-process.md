---
status: completed
package: eta_process
consumer: Leash milestone 1 (chrome-p2n4, chrome-9ex7, chrome-qo4q, chrome-2z2z, chrome-6lfk, chrome-b288)
---

# Process: a child process as a scoped resource, with supervision

## Problem Statement

Leash launches Chrome with a pipe pair on child file descriptors 3 and 4, must know when it dies, must relaunch it under a schedule, and must stop it gracefully on shutdown. Eio can spawn with inherited fds (`Eio_unix.Process.spawn_unix`) but ties the child to a Switch whose release sends SIGKILL at once, from the cancellation handler of a daemon fiber — so a naive resource races its own SIGTERM finalizer.

## Solution

`eta_process`: `Child`, a scoped child process owning a private Switch so that termination is SIGTERM, a bounded wait, then SIGKILL, in that order, in every exit path; and `Supervised`, which reruns a child under a `Schedule`, exposes a generation counter and a stream of lifecycle events.

## User Stories

1. As a service author, I want `Child.spawn ~sw ~mgr ~argv ?env ?cwd ~fds` to start a process with extra inherited descriptors mapped to chosen child fd numbers (3 and 4 for Leash), so that pipe-based protocols work. ^nproc-1x05
2. As a service author, I want stdout and stderr of the child available as Eio flows (or discarded), so that logs can be forwarded. ^nproc-giyu
3. As a service author, I want `Child.await` to return a typed exit (`Exited of int | Signaled of int`), so that "crashed" and "exited 0" are distinguishable. ^nproc-bqik
4. As a service author, I want the child's lifetime to be a private Switch inside the resource, released last, so that Eio's SIGKILL-on-release is the backstop after my own termination sequence, never a race with it. ^nproc-e5zc
5. As a service author, I want release to send SIGTERM, wait up to a configured grace duration on the given clock, then SIGKILL, then reap, so that a well-behaved child exits cleanly and a stuck one still dies. ^nproc-xmat
6. As a service author, I want release to run to completion even when the enclosing scope is being cancelled, so that no child is left behind. ^nproc-71a7
7. As a service author, I want invalid fd mappings (negative, duplicate, colliding with 0–2) rejected before spawn with a typed error, so that misuse is caught early. ^nproc-7bkl
8. As a service author, I want `Supervised.start ~sw ~clock ~schedule ~spawn` to run a child, and when it exits rerun `spawn` after the schedule's delay, until the schedule stops or the scope ends, so that Chrome comes back on its own. ^nproc-cyeq
9. As a service author, I want a monotonically increasing generation number, incremented on each successful spawn, readable at any time, so that handles can be bound to a browser incarnation. ^nproc-msz4
10. As a service author, I want a stream of events `Started of generation | Exited of generation * exit | Gave_up of Cause`, so that a registry can react to loss. ^nproc-pnnm
11. As a service author, I want stopping the supervisor to terminate the current child with the same SIGTERM-grace-SIGKILL sequence and never spawn again, so that shutdown is orderly. ^nproc-svva
12. As a test author, I want the spawn function injectable (the fake `Eio.Process.mgr` from `eta_test`), so that supervision is tested without real processes, and one real-process test (a shell script that ignores SIGTERM) proves the escalation. ^nproc-ypzm

## Implementation Decisions

- `Child` uses `Eio_unix.Process.spawn_unix` with `fds` mappings; two unidirectional pipes for the Leash case, parent closes child ends promptly.
- Private Switch: created inside `spawn`, stored in the child value; the resource's release (registered on the caller's `sw` via `Switch.on_release`) runs terminate → wait(grace, clock) → kill → await, then ends the private Switch. Under cancellation `on_release` still runs (Eio guarantees release handlers), so nproc-71a7 follows; verify with a test.
- Signal through `Eio.Process.signal` (PID reuse safe), never a raw `Unix.kill` on a stored pid.
- `Supervised` is `Retry.repeat` in disguise: a loop over the schedule; the event stream is an `Eio.Stream` with a bounded capacity and documented overflow (drop oldest and count).
- Exit is 0-grace-safe: grace 0 means SIGKILL immediately.

## Testing Decisions

- Fake-manager tests for supervision, generation, events, stop-never-respawns — nproc-cyeq, nproc-msz4, nproc-pnnm, nproc-svva.
- Real-process tests (`sleep`, a script trapping SIGTERM, a script exiting 3) for spawn/fds/exit/escalation, with a small real grace — nproc-1x05, nproc-bqik, nproc-xmat, nproc-e5zc, nproc-71a7 (cancel the scope from another fiber mid-run and assert the child is reaped).
- Fd tests: write on 3, read on 4 through the pipes with a `cat`-like helper — nproc-1x05; invalid mappings — nproc-7bkl.

## Out of Scope

Process groups, ptys, environment sanitization, Windows.

## Further Notes

The v1 ticket `process-scoped-child` (`v1:docs/issues/process-scoped-child/`) contains the Eio findings that led here; its requirement texts are superseded by these stories.

Verification: `nix develop -c env DUNE_BUILD_DIR=_build_process dune build @install` passed.
Verification: `nix develop -c env DUNE_BUILD_DIR=_build_process dune test test/process` passed (11 tests).
