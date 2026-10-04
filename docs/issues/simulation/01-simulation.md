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

1. As a test author, I want `Ox_test.Sim.run ~seed (fun world -> ...)` handing me one value that carries the mock clock, the mock network and the schedules, with every source of nondeterminism in the test taken from it, so that a test is deterministic by construction. ^nsim-mp01
2. As a test author, I want the world to inject cancellation at a chosen suspension point and to sweep every suspension in a run (`~cancel_at:(`Nth n | `Never | `All)`), so that "cancelled in the middle of a handshake" is a case the suite enumerates instead of one a human imagines. ^nsim-cxd5
3. As a test author, I want seeded network and process faults — short reads, split frames, delayed and reordered delivery, abrupt close, a child dying at a chosen moment — so that the half-frame and keepalive classes have a generator rather than a fixture. ^nsim-wnmx
4. As a test author, I want simulated time to advance on the mock clock, so that a thirty-minute keepalive budget is asserted in milliseconds and a campaign covers hours of simulated time in a minute of real time. ^nsim-11lz
5. As a maintainer, I want a failure to print its seed and the exact replay command, and the seed to be accepted from `OX_SIM_SEED`, so that a nightly failure is reproduced locally without guesswork. ^nsim-1lom
6. As a maintainer, I want `dune test` to run a small fixed seed set per suite in seconds while `@stress` runs the wide sweep, so that the gate stays fast and depth still exists. ^nsim-54gd
7. As a maintainer, I want each of ox's five historical bug classes to have a simulation case that fails on the pre-fix code and passes after it — lost wake-up, keepalive under flood, half frame, shared duplex buffer, cancellation during cleanup — so that the simulator is proven against bugs we had, not only against invented ones. ^nsim-v5mi
8. As a test author, I want `docs/testing.md` to show how to add a simulation case and which seams must come from the world, and row 86's checklist to require one for new transport or concurrency code, so that the default is the default in practice. ^nsim-8842

## Implementation Decisions

Built on `Eio_mock` (clock, network, flows) and the existing `Ox_test` fakes, with `qcheck-core` generators driving the seeds as row 60 already does. Control of **fiber interleaving** is not claimed unless row 86's research (slot 03) finds a way to force a schedule under Eio; without it, determinism covers time, I/O, faults and cancellation points, and that limit is written in `docs/testing.md` rather than papered over. Real sockets and real processes keep their separate suites on purpose (`docs/why-ox.md` §4).

## Out of Scope

Replacing the real-fixture process and socket tests; performance benchmarks.
