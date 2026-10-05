---
status: ready
package: ox (Timeout), ox_lint (race diagnostic)
consumer: Ox deadline doctrine; Pie Ptt_loop with a monotonic clock
---

# Monotonic deadlines and an honest race diagnostic

## Problem Statement

Pie holds only an Eio monotonic clock while waiting for input. Ox.Timeout.timeout accepts a wall clock, so Pie must express its deadline by racing Mono.sleep against input. Changing clock kind would make its elapsed-time deadline depend on wall-clock corrections. The ox-race-deadline diagnostic also attributes first-success selection to every matched combinator, although race_first and Eio.Fiber.any select the first settlement, including a typed failure.

## Solution

Add timeout_mono beside the unchanged wall-clock timeout, delegating to upstream Eio monotonic timeout values. Keep the existing call shape and result channel. Document the implementation-derived cancellation and switch ownership contract. Explain both race selection policies accurately and direct each clock kind to its matching timeout API.

## User Stories

1. As a service author holding an Eio monotonic clock, I want Ox.Timeout.timeout_mono ~clock duration f with the same result, cancellation and switch interaction as timeout, without changing timeout's signature or behaviour, so that elapsed-time deadlines remain independent of wall-clock corrections. ^nmono-8jcy
2. As a maintainer, I want deterministic monotonic timeout tests for returned values/errors, defects, deadline expiry, external cancellation, nested deadlines, cleanup and caller-owned switches, including forward and backward wall-clock jumps, so that the new API preserves upstream semantics and proves its clock choice. ^nmono-r2pk
3. As a reader of ox-race-deadline, I want the diagnostic and rule page to distinguish race's first success from race_first/Fiber.any's first settlement and show the wall/monotonic replacements, so that the rule teaches the actual API rather than a false selection policy. ^nmono-m4tg

## Implementation Decisions

- A sibling function preserves all five consumers' existing timeout calls and makes clock choice visible without making the common wall-clock call wordier.
- Eio 1.6 has no Mono.with_timeout. Its Time.Timeout.seconds and Time.Timeout.run use Mono.sleep_span and the same Fiber.first machinery as Time.with_timeout; use those rather than introducing an Ox-owned race.
- Timeout owns no switch. A switch created inside the callback is unwound before timeout returns, while resources registered on an enclosing switch remain owned by that switch. Cleanup defects and external interruption keep Eio's semantics; no rollback is promised.
- Tests advance backend-owned virtual time, not the machine clock. The wall-jump cases control distinct mock wall and monotonic clocks under Ox_test.run.

## Out of Scope

Consumer changes, new dependencies, changes to the wall-clock timeout implementation/signature, and allow-list entries. No staging or commit is performed in this delivery.
