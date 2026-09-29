---
status: ready-for-agent
package: ox_app (Door, with_powerbox), ox (Schedule)
consumer: every consumer on EIO_BACKEND=posix (all of them); Pie's prepared-text hang
---

# Posix wake-up tick, and jitter back to compile time

## Problem Statement

Pie's research (pie docs/research/2026-09-29-sigchld-ppoll-race/REPORT.md) shows a dependency-level lost wakeup: under Eio's posix backend, iomux's `ppoll` can enter the kernel after SIGCHLD was recorded but before its OCaml handler ran, and sleep forever with a finished child unreaped. A plain-Eio reproducer hung 22/50; Pie's prepared-text suite 13/50. Every service on this machine runs `EIO_BACKEND=posix` (memlock is 8 MiB; io_uring's pinned buffers count against it), so every consumer is exposed. The linux backend reaps via pidfd and is immune by construction. Separately, row 53 made a jittered `Schedule` without a random source fail at runtime instead of at compile time.

## Solution

The Door and `with_powerbox` start a daemon fiber on the posix backend that sleeps a bounded interval in a loop, so the scheduler never blocks in `ppoll` without a timeout and a pending signal is handled within that interval. `jittered` takes its random source as an argument. The upstream report is written for the operator to file.

## User Stories

1. As an operator, I want every Door program and every `with_powerbox` program on the posix backend to run a wake-up daemon fiber sleeping 50 ms (configurable, `0` disables) so that a lost SIGCHLD wakeup delays a child's reaping by at most that interval instead of forever. ^nwake-27rc
2. As an operator, I want the tick not started on the linux backend, and the choice logged once at start (`backend=posix wakeup_ms=50`), so that it costs nothing where it is not needed and is visible where it is. ^nwake-y4cx
3. As a maintainer, I want the plain-Eio reproducer from Pie's research added to ox as a stress test that spawns 1,000 short children per run under the Door and passes 50/50 runs with the tick (bounded by an external timeout per run), so that the mitigation is proven. ^nwake-fz0j
4. As a maintainer, I want Pie's prepared-text stress alias (pie-stress.patch) applied to Pie and passing 50/50 against the new ox, recorded here, before the operator is asked to swap Pie's binary, so that the production fix is shown on the case that hung. ^nwake-9uvx
5. As a service author, I want `Schedule.jittered` (and every jitter kind) to take the random source as a required argument, removing the runtime failure introduced in row 53, so that a missing random source is a compile error again. ^nwake-8qx5
6. As the operator, I want an upstream issue text for iomux (and a short note for Eio) in `docs/upstream/iomux-ppoll-sigchld.md`: the mechanism, the gdb evidence, the standalone reproducer, the experimental patch and its known limits, so that I can file it; the agent does not post it. ^nwake-i8u6

## Implementation Decisions

- Backend detection: `Eio_main` reports which backend it chose (or `EIO_BACKEND`); the tick is `Fiber.fork_daemon` with `Eio.Time.sleep`.
- The tick is a mitigation, recorded as such in `docs/modes.md`'s upstream-gap list with a pointer to the issue; remove it when iomux is fixed or the services move to the linux backend (which needs memlock raised in nixos-config).

## Testing Decisions

- Story 3's stress test behind a dune alias (not the default test run); the Door test asserts the tick starts on posix only.

## Out of Scope

Patching iomux or vendoring it; switching services to the linux backend; raising memlock.
