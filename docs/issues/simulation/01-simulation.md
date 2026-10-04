---
status: ready
package: ox_test, ox, ox_http, ox_ipc, ox_rpc
consumer: Ox (ADR-0010; the bug classes of row 60)
---

# Seeded deterministic simulation is the default shape of a concurrency test

## Problem Statement

Every bug ox has had since the master switch was temporal: a lost ppoll/SIGCHLD wake-up, a keepalive flood dying after eleven minutes, half frames, two fibers on one ciphertext buffer, a cancellation arriving at the wrong moment. No OCaml type system sees any of them, and row 60's answer — property, fuzz, flood and storm suites — sits behind an opt-in `@stress` alias outside `dune test`, on one fixed seed. The class of bug that actually occurs is tested last, longest and least often.

## Solution

A seeded deterministic world in `ox_test` — mock clock, mock network, scripted processes, a fault schedule and a cancellation schedule — in which transport and concurrency tests are written by default: short in `dune test`, wide and time-accelerated in `@stress`, with the failing seed printed and replayable by one command.

## User Stories

1. As a test author, I want `Ox_test.Sim.run ?seed ?faults (fun world -> ...)` over `Eio_mock.Backend.run_full` — whose scheduler is already single-threaded, virtual-clocked and deadlock-detecting — handing me the clock, the network, the fakes and the decision log, so that a test is deterministic by construction and a hang is a failure rather than a timeout. ^nsim-mp01
2. As a test author, I want the seed to reach the *decisions*, not only the data: one `Random.State.t` per run, consulted through `Sim.decide` at every faultable operation, with every decision recorded — FDB's buggify sites and TigerBeetle's per-tick roll. Without this, `Eio_mock` replays the same script on every run, which is why ox's current suites cannot find an ordering a human did not write. ^nsim-cxd5
3. As a test author, I want per-boundary fault classes decided from the seed — clock (`Delay`, `Wake_late`), flow (`Partial`, `Eof`, `Fail`, `Yield`), net (`Drop`, `Reorder`, `Delay`, `Connect_fail`), cancel (`Cancel_at`) — and a per-run **swarm mask** enabling a random subset, because FDB reports that an excessive fault rate collapses the explored state space while the Antithesis/etcd case shows raising the two relevant rates is what surfaces a rare bug. ^nsim-wnmx
4. As a test author, I want simulated time to advance on the mock clock, which `run_full` already auto-advances when the run queue empties, so that a thirty-minute keepalive budget is asserted in milliseconds and a campaign covers hours of simulated time in a minute of real time. ^nsim-11lz
5. As a maintainer, I want a failure to print the seed, the exact replay command and the decision log, and the seed to come from `OX_SIM_SEED` — extending `test/stress/stress_support.ml`, which already prints and accepts one, rather than inventing a second convention. ^nsim-1lom
6. As a maintainer, I want an **unseed check**: at a low rate, run the same scenario twice in one process with one seed and assert the trace digest and the PRNG position are equal, failing with the first differing line. FDB and Dropbox's Trinity both do this, and in OCaml it is the only cheap detector of the things that silently break determinism — `Random.self_init`, randomized `Hashtbl` seeds, a clock read outside a capability, a stray `Domain.spawn`, a real socket a test forgot to fake. ^nsim-54gd
7. As a maintainer, I want each of ox's five historical bug classes to have a simulation case that fails on the pre-fix code and passes after it — lost wake-up, keepalive under flood, half frame, shared duplex buffer, cancellation during cleanup — and a coverage counter per fault class asserted non-zero on the long run, because a fault that can never fire is worse than no fault: it is a false guarantee. ^nsim-v5mi
8. As a test author, I want `docs/testing.md` to show how to add a case, which seams must come from the world, and what the harness cannot do, with row 86's checklist requiring a case for new transport or concurrency code. ^nsim-8842
9. As a maintainer, I want the build to fail when ox consumes a capability for which the simulated world has no fake — `Eio_mock` has no filesystem fake, and `Cap_sys.urandom` and the `Cap_stdlib.Random` wrappers are unfaked today — so that a new dependency on the outside world cannot quietly leave the simulation. ^nsim-4qjt

## Implementation Decisions

Eio already supplies the precondition: its README's determinism note states that within a domain fibers are scheduled deterministically, and that a program using only Eio's APIs can behave non-deterministically only if given a capability to do so. So one domain plus fakes is deterministic, and the harness adds the three things `Eio_mock` lacks: a seed that reaches decisions, faults with a swarm mask, and the replay record.

**Correction to the row's first framing:** "inject a fault at every suspension point" is not what the deterministic-simulation projects do, and no primary source states it. FDB injects at explicit code sites and at I/O; TigerBeetle rolls per tick; Antithesis at I/O exchange points and interrupts; madsim at every scheduling decision. The Eio-shaped equivalent is therefore **two** mechanisms: seeded faults per mocked operation, and explicit cancellation points (`Cancel_at`, and capnp-rpc's convention of a `fork_with_cancel` handle plus `Fiber.await_cancel ()` placed where the test wants the cancellation).

Controlling **fiber interleaving** is a separate, last and test-only option: a seeded first-in-random-out scheduler written over `Eio.Private.Effects` (Eio's own tree already writes a scheduler over those three effects twice, in `lib_eio/mock/backend.ml` and `lib_eio/tests/dscheck/fake_sched.ml`), and `Eio.Private` carries no stability promise. It is not part of the first version, and until it exists `docs/testing.md` says plainly that determinism covers time, I/O, faults and cancellation points but not interleaving.

`dscheck` is not applicable to fiber code: its soundness conditions require atomic-only communication and lock-freedom. `qcheck-core` drives the seeds as row 60 already does; `qcheck-stm` models are a later addition. No new dependency.

Evidence: [research/03-simulation.md](../usage-rules/research/03-simulation.md).

## Out of Scope

Replacing the real-fixture process and socket tests; performance benchmarks; hypervisor- or `rr`-style replay; `libc` interposition (madsim's mechanism, which needs Cargo-style patching).
