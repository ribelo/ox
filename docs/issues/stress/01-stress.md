---
status: ready-for-agent
package: ox (Concurrent, Scope, Actor, Channel), ox_http (h1, ws, tls), ox_ipc, ox_rpc
consumer: every consumer; the bug class found in rows 45, 55, 57, 59
---

# Stress and fuzz under the transports and the concurrency core

## Problem Statement

Every bug found in ox since the master switch was in the same class — cancellation, lost wakeups, half frames, keepalive floods — and lived in the code with the thinnest tests: `Concurrent`, `Scope`, the WebSocket and TLS layers, the IPC listener. Rows 57 and 59 added transport behaviour with tests written by the same agent that wrote the code. ox has a twelfth of v1's test volume; v1's stress suites under `test/stress` exercised exactly these seams and were not ported.

## Solution

A stress layer behind a dune alias (not the default run): property tests over `Concurrent` and `Scope` outcome patterns, fuzzed frames into the h1 and ws parsers, a keepalive flood and a half-close storm against a live ws pair, a cancel-storm against `Actor`/`Channel`, and a many-client storm against `ox_ipc`. Ported from v1's suites where one exists.

## User Stories

1. As a maintainer, I want a `@stress` alias running suites that take up to a minute each, excluded from `dune test`, so that depth does not slow the gate. ^nstress-xn75
2. As a maintainer, I want QCheck properties over `par`/`race`/`all`/`for_each` and `supervised_error` with generated outcome patterns (success, typed error, exception, external cancel, at every position and timing), asserting the combinator law and that every fiber is awaited, so that the law is machine-checked beyond the fixed table. ^nstress-mvpj
3. As a maintainer, I want the h1 request/response parser and the ws frame parser fuzzed with Crowbar (mutated valid frames, truncation at every byte, oversized lengths), asserting no exception escapes and every rejection is a typed error, so that malformed peers cannot crash a service. ^nstress-ln4z
4. As a maintainer, I want a live ws pair under a keepalive flood and simultaneous half-closes for 30 s, asserting the row-57 budget holds and both ends release, so that Pie's long recordings have a test that resembles them. ^nstress-0uv9
5. As a maintainer, I want a cancel storm over `Actor` and `Channel` (thousands of asks with random caller cancellation), asserting no pending ask is lost and the actor's state stays consistent, so that Leash's registry has coverage at its seam. ^nstress-ttto
6. As a maintainer, I want 200 concurrent clients against an `ox_ipc` listener with random disconnects mid-request, asserting every connection is answered or cleanly dropped and the budget reply is written, so that the L36 ten-client test has a bigger sibling. ^nstress-kcr6
7. As a maintainer, I want v1's `test/stress` inventoried, each suite marked ported / superseded / not applicable with a reason, so that nothing valuable is silently dropped. ^nstress-gylw

## Implementation Decisions

- QCheck and Crowbar are already in the switch; no new dependency. Fuzz corpora committed under `test/stress/corpus`.
- Every stress suite has a fixed seed in the alias and accepts `OX_STRESS_SEED` for exploration.

## Testing Decisions

- The suites are the deliverable; a found bug is fixed in its row with a regression test in the default run.

## Out of Scope

AFL campaigns; performance benchmarks.
