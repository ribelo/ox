---
status: ready
package: docs (spike); measures ox, Leash, nema
consumer: Ox (ADR-0010); decides row 71
---

# Spike: what the suspension token costs

## Problem Statement

`suspend-token` (row 71) makes suspending inside a critical section a compile error by requiring `~io : Ox.Io.t` (a `yielding` value) on every operation that may suspend. The guarantee is verified (ADR-0010); the cost is not. Caps, the closest precedent, cost Leash about 150 `~caps` threading sites and grip 229 in 5.9 kloc (`docs/caps.md`, ^ncaps-21nk). Row 71 is built in ox either way; whether consumers migrate is decided on this spike's numbers.

## Solution

Measure, on ox and on the two consumers already on ox with the most concurrency (Leash, nema), how many signatures and call sites would carry `io`, and prototype the migration of one real module per consumer to see the code it produces.

## User Stories

1. As a maintainer, I want every operation in ox that may suspend listed (Ox and the Eio calls ox makes: channel, stream, promise, mutex, condition, sleep, timeout, I/O on flows and sockets, blocking pool), so that the token's reach is known. ^ntokcost-3m7a
2. As a maintainer, I want, for ox, Leash and nema separately: the number of functions that would need `~io` in their signature (transitively: a function that calls one that suspends), the number of call sites passing it, and both per kloc, beside the caps numbers, so that the cost is comparable to a cost already paid. ^ntokcost-k2xd
3. As a maintainer, I want the critical sections the token would protect counted (actor handlers, agent closures, mutex sections, `Cancel.protect`, status functions) and any current suspension inside one listed with file:line, so that the benefit is measured too. ^ntokcost-9pfv
4. As a maintainer, I want one module per consumer migrated in a scratch copy with the ADR-0010 token and explicit `bind ... [@nontail]` (the `ppx-let` expansion), compiled with the pinned compiler, and its diff summarised, so that the code it produces is seen, not imagined. ^ntokcost-w4hn
5. As a maintainer, I want a recommendation — migrate consumers, keep the token inside ox only, or drop it — with the numbers that decide it, so that row 71's consumer stories have a basis. ^ntokcost-c8ue

## Findings

(Filled by the spike.)
