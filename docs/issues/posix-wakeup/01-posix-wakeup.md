---
status: completed
package: ox_app (Door), ox (Schedule, Retry)
consumer: every consumer on EIO_BACKEND=posix (all of them); Pie's prepared-text hang
---

# Posix wake-up tick, and jitter back to compile time

## Problem Statement

Pie's research (pie docs/research/2026-09-29-sigchld-ppoll-race/REPORT.md) shows a dependency-level lost wakeup: under Eio's posix backend, iomux's `ppoll` can enter the kernel after SIGCHLD was recorded but before its OCaml handler ran, and sleep forever with a finished child unreaped. A plain-Eio reproducer hung 22/50; Pie's prepared-text suite 13/50. Every service on this machine runs `EIO_BACKEND=posix` (memlock is 8 MiB; io_uring's pinned buffers count against it), so every consumer is exposed. The linux backend reaps via pidfd and is immune by construction. Separately, row 53 made a jittered `Schedule` without a random source fail at runtime instead of at compile time.

## Solution

The Door starts a daemon fiber on the actual posix backend that sleeps a bounded interval in a loop, so the scheduler does not enter an indefinite `ppoll` and a pending signal can be handled on a later tick. This is a scheduling mitigation, not a hard real-time bound. `with_powerbox` deliberately stays runtime-free, as recorded below. Jitter constructors require their random source. The upstream report is written for the operator to file, not submitted.

## User Stories

1. As an operator, I want every Door program and every `with_powerbox` program on the posix backend to run a wake-up daemon fiber sleeping 50 ms (configurable, `0` disables) so that a lost SIGCHLD wakeup delays a child's reaping by at most that interval instead of forever. ^nwake-27rc
2. As an operator, I want the tick not started on the linux backend, and the choice logged once at start (`backend=posix wakeup_ms=50`), so that it costs nothing where it is not needed and is visible where it is. ^nwake-y4cx
3. As a maintainer, I want the plain-Eio reproducer from Pie's research added to ox as a stress test that spawns 1,000 short children per run under the Door and passes 50/50 runs with the tick (bounded by an external timeout per run), so that the mitigation is proven. ^nwake-fz0j
4. As a maintainer, I want Pie's prepared-text stress alias (pie-stress.patch) applied to Pie and passing 50/50 against the new ox, recorded here, before the operator is asked to swap Pie's binary, so that the production fix is shown on the case that hung. ^nwake-9uvx
5. As a service author, I want `Schedule.jittered` (and every jitter kind) to take the random source as a required argument, removing the runtime failure introduced in row 53, so that a missing random source is a compile error again. ^nwake-8qx5
6. As the operator, I want an upstream issue text for iomux (and a short note for Eio) in `docs/upstream/iomux-ppoll-sigchld.md`: the mechanism, the gdb evidence, the standalone reproducer, the experimental patch and its known limits, so that I can file it; the agent does not post it. ^nwake-i8u6

## Implementation Decisions

- Backend detection uses `Eio.Stdenv.backend_id` from the runtime actually selected, not `EIO_BACKEND`; this covers automatic linux-to-posix fallback. `Fiber.fork_daemon` sleeps with `Eio.Time.sleep` on an outer switch, outside the program/signal-cancellation switches, and is cancelled only after their protected cleanup has returned. A daemon cannot keep that outer switch alive.
- Door configuration is `?wakeup_ms:int`, then `OX_POSIX_WAKEUP_MS`, then 50 ms. `0` disables it; negative or malformed values fail fast. Only service-program startup logs actual `backend` and effective `wakeup_ms`, once through the Door's journal logger, subject to `?log_level` and `?journal_level`; the record is not copied to telemetry. Owned/client/config commands start the ticker silently and keep stderr clean. Runtime-owning callers can explicitly install the same mitigation with `Ox_app.posix_wakeup ~sw ?interval_ms ?logger env`; without an explicit logger the helper is silent.
- **Deliberate deviation from story 1:** `with_powerbox` stays runtime-free and does not start a ticker. Its current consumer, grip, runs synchronous code on the calling thread and Eio only in its OTLP systhread; it spawns no children under Eio. Merely wrapping that code in `Eio_main.run` would block the scheduler so its daemon could not fire, while a genuine conversion would rewrite grip into another runtime model. Its interface documents this limit; callers owning an Eio runtime use `posix_wakeup`. The Door path meets the process-reaping intent.
- `Schedule.jittered ~random` (all `~kind` values) and `Schedule.decorrelated_jitter ~random` capture the supplied mutable source at construction, without drawing then or at `Schedule.start`. `Schedule.start`, `Retry.retry` and `Retry.repeat` no longer accept an optional source. Stepping consumes captured sources; drivers from the same schedule share the source, so independent streams need separate/copied sources and fresh schedules.
- The tick is a mitigation, recorded as such in [modes](<../../modes.md>)' upstream-gap list with a pointer to the issue; remove it when iomux is fixed or the services move to the linux backend (which needs memlock raised in nixos-config).

## Testing Decisions

- Story 3 lives behind `@stress-posix-wakeup` (not default `runtest`), with `@stress-posix-wakeup-disabled` disabling the tick. Each population has 50 runs, 1,000 short children per run and a 5-second OS timeout with a 1-second kill backstop. The Door tests assert actual-backend detection, cadence, disabled/linux no-daemon behavior, precedence, service-only journal logging, journal filtering, owned-command empty stderr with the ticker enabled, rejection and SIGTERM during cancellation-protected child cleanup.
- Pie's research `pie-stress.patch` is applied, preserving its stress alias and runner behavior. Its test-only `Pie_test_runtime.run` owns Eio plus an outer switch with silent `posix_wakeup`; 94 runtime sites in eleven child/process-manager test harnesses (including prepared-text and focus-rules) now use it. Installing new Ox alone cannot add a ticker to a test that never enters the Door. The original audit found 197 direct `Eio_main.run` sites in 33 test files and none in production; the remaining 103 sites are non-child/network/audio/config or Unix-wait-only tests. Pie's production CLI already enters through `Ox_app.run_with_args`.
- Compiler checks reject multiplier jitter, jitter-kind and standalone decorrelated jitter without `random:Random.State.t`; a control covers all constructors with a source. Existing deterministic schedule and Retry tests move sources to construction. Nema's embedding retry is the only affected production callsite among Leash, Pie, nema, inn and grip; it passes its existing source into `jittered` and uses plain `start`.

## Acceptance Evidence (2026-09-29, Europe/Warsaw)

| Population | Passed | OS timeouts | Other failures |
| --- | ---: | ---: | ---: |
| Plain Eio control, no Door/tick, 50 × 1,000 children | 47/50 | 3/50 | 0 |
| Door, 50 ms tick, 50 × 1,000 children | 50/50 | 0/50 | 0 |
| Door, tick disabled, 50 × 1,000 children | 50/50 | 0/50 | 0 |
| Pie prepared-text, installed old Ox, unmitigated direct-Eio harness | 29/50 | 21/50 | 0 |
| Pie prepared-text, private new Ox and explicit test-runtime mitigation | 50/50 | 0/50 | 0 |

All these current populations use a 5-second external timeout with a 1-second kill backstop. Door enabled and disabled populations also pass 50/50 under bounded CPU contention; sequential disabled runs remain 50/50. **The Door-hosted disabled population did not reproduce the race.** Its topology can change timing, but the reason was not established, so that comparison does not by itself prove causality. The plain-Eio control supplies the current failing evidence and Pie's 29/50 → 50/50 comparison the consumer mitigation evidence. The three control timeouts were not individually traced. See [stress evidence](<../../../test/stress-posix-wakeup/README.md>) for commands, conditions and limits. Earlier research with a native experimental wrapper is separate evidence, not the new-Ox gate.

- Ox: `@install`, full posix `dune test`, `@fmt` and caps gate pass; the suite includes 185 core tests, 44 Door tests and 12 wakeup tests. The missing-RNG compile failures and constructor control pass. Caps checks use their documented lexical fallback for five Semgrep `PartialParsing` files, with no silent skip.
- Leash, Pie, inn and grip: build/install, full posix tests and caps gates pass against private `/tmp/ox-r55/lib`; Leash and Pie formatting gates pass. inn and grip have no `.ocamlformat`. Pie's full suite passes after centralizing test-runtime ownership; its main suite has 127 cases and prepared-text 21. The client `stderr empty` assertion is unchanged.
- Nema: build/install, full posix tests and caps pass against `/tmp/ox-r55-nema/lib`, rebuilt from this Ox tree inside Nema's Nix shell. The main prefix cannot be mixed with Nema's Nix Eio/Mtime interfaces. Nema's pre-existing isolated-home runner requires default `_build` rather than `DUNE_BUILD_DIR`; this is recorded, not silently worked around in production. Nema has no `.ocamlformat`; its requested `@fmt` check fails on 15 pre-existing untouched Dune layouts (tests, Ladybug tests, the binary and one scratch experiment). Those unrelated files are not reformatted; diagnostics are retained in [Nema formatting evidence](</tmp/ox-r55-evidence/nema-fmt.log>).
- Only Nema's embedding-retry production callsite needs a source migration. Pie's additional changes are test-only runtime support and the research stress alias/runner; Leash, inn and grip need no source edits.
- The [upstream issue draft](<../../../docs/upstream/iomux-ppoll-sigchld.md>) includes the standalone repro, pending-signal/gdb evidence, inline experimental C patch, single-domain/Linux and internal-runtime-API limits, and an Eio filing note. It has not been submitted.

No shared install, service backend/memlock change, binary swap, upstream posting or commit is performed by this delivery. The private prefixes and experiment evidence are retained, including [final Pie suite evidence](</tmp/ox-r55-evidence/pie-full-test.log>), [final 50-run stress evidence](</tmp/ox-r55-evidence/pie-prepared-text-stress.log>) and the archived baseline logs in `/tmp/ox-r55-evidence/prepared-text-baseline/`. Isolated `_build_r55` directories are removed after recording evidence; Nema's existing default `_build` is not removed.

## Out of Scope

Patching iomux or vendoring it; switching services to the linux backend; raising memlock.
