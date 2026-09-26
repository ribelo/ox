---
status: completed
verification: |
  2026-09-26: commit 181fcc33 gated in a clean worktree — dune build @install, dune test (all suites) and dune build @fmt green.
  Census leak test fails on a deliberate leak; real SIGTERM/SIGINT fixture exits 0; Stopped/Closed delivered once, last.
package: eta_test, eta_app, eta_process, eta_rpc, eta_ipc (docs only)
consumer: Leash milestone 1 (chrome-qo4q, chrome-2z2z, chrome-b288) and its tests
---

# Attack the known limits from rows 0–8

## Problem Statement

The delivery of rows 0–8 recorded five limits. Four are worth removing now, before Leash builds on the shapes: the fiber census only counts fibers started through `fork_run`; the Door's signal test never sends a signal; the `eta_process` and `eta_rpc` event streams never say they have ended, forcing consumers to stop reading under their own switch; and `eta_ipc`'s ownership checks assume no hostile same-user process — which is the trust boundary, not a defect, and only needs saying.

## Solution

A real fiber census through Eio's runtime events; a real-signal Door test through `eta_process`; terminal events on both streams; one paragraph in `eta_ipc`'s interface.

## User Stories

1. As a test author, I want `Eta_test.assert_no_fibers_left` to count every Eio fiber created and exited in the process, using `Runtime_events` and Eio's `create_fiber`/exit trace events, so that a leaked fiber anywhere fails the test. ^nlimit-gmur
2. As a test author, I want the census to be scoped: `Eta_test.with_census f` returns the count of fibers still alive that were created during `f`, so that unrelated fibers do not cause false failures. ^nlimit-9e19
3. As a service author, I want the Door tested with a real `SIGTERM` and a real `SIGINT`: a test executable using `Eta_app.run` is spawned through `eta_process`, signalled, and its exit code and journal output asserted, so that the signal path is proven end to end. ^nlimit-s3f4
4. As a service author, I want `Supervised.events` to deliver a final `Stopped` event after `stop` or after `Gave_up`, and the stream to be documented as ending there, so that a consumer's reader loop terminates on its own. ^nlimit-a407
5. As a service author, I want `Correlator.notifications` to deliver a final ``Closed of close_reason`` element (the stream element type becomes a variant of message or closed) when the transport closes, so that a reader loop terminates on its own. ^nlimit-ruzp
6. As a service author, I want `Child.stdout`/`stderr` sources documented as reaching end-of-file at retirement, with a test, so that a log-forwarding fiber terminates. ^nlimit-nzur
7. As an operator, I want `eta_ipc`'s interface to state its trust boundary — same-user processes are trusted; the checks defend against stale state, accidents and other users, not against a hostile process of the same user — so that nobody expects more. ^nlimit-ylvw
8. As a kernel maintainer, I want the earlier `fork_run`-only census removed (not kept as a second path), so that there is one census. ^nlimit-i8pu

## Implementation Decisions

- Census: `Runtime_events.start ()` in the test process, a cursor with callbacks on Eio's custom events (see `eio/core/trace.mli`: `create_fiber`, and the exit event), a counter keyed by fiber id; `with_census` snapshots before and after. If the pinned Eio does not emit an exit event, record that in the spec and count against `create_fiber` plus `Fiber` completion observed via `Runtime_events` "ring" of the fiber's context; stop if neither is available and report.
- Real-signal test: a small test executable in `test/app/` built with `eta_app`; the test spawns it with `Child.spawn`, waits for a "ready" line on stdout, signals with `Child.signal` (which calls `Eio.Process.signal` on its retained process handle), asserts exit 0 for SIGTERM/SIGINT and the journal's stop line.
- Stream terminal events are additive variants; `Stopped`/`Closed` is delivered exactly once, last.

## Testing Decisions

- Each story has a test citing it; the census test deliberately leaks a fiber and expects failure.

## Out of Scope

Hardening `eta_ipc` against same-user attackers; a tracing UI.
