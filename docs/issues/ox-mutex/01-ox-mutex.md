---
status: ready
package: ox
consumer: every consumer (Ox-internal; ADR-0010)
---

# `Ox.Mutex`: branded guarded data and `local once` critical sections

## Problem Statement

A mutex in the tree guards data by convention: nothing stops a read of `Tls_flow`'s buffers without `write_mu`, and nothing stops a Stdlib `Mutex` being held across a suspension, which blocks the whole domain. Jane Street's `capsule` and `await` solve the first by typing (data of brand `'k` is reachable only with a `'k` access that exists only while the lock is held) and the second by passing the right to suspend as a value; neither package is installable on 5.4.0+ox (ADR-0010).

## Solution

`Ox.Mutex`, single-domain, over `Eio.Mutex`, shaped after `Capsule` + `Await.Mutex` so that a later swap is mechanical, with critical sections `@ local once unyielding`. `Ox.Cancel.protect` with the same modes.

## User Stories

1. As a service author, I want `Ox.Mutex.create : unit -> packed` (`P : 'k t -> packed`), `Mutex.Data.create : 'k t -> 'a -> ('a, 'k) Data.t`, `with_access : 'k t -> ('k Access.t @ local -> 'b) @ local once unyielding -> 'b` and `Data.get : access:'k Access.t @ local -> ('a, 'k) Data.t -> 'a`, so that touching guarded data without its lock is a compile error. ^ncrit-ihf2
2. As a service author, I want data of one mutex's brand refused with another mutex's access, and the access refused outside the critical section, so that the lock that guards a datum is part of its type. ^ncrit-1px5
3. As a service author, I want `Ox.Cancel.protect : ?deadline:(clock * Duration.t) -> (unit -> 'a) @ local once -> 'a` over `Eio.Cancel.protect` — with the deadline because Trio's shielded cleanup takes one and the failure modes on either side are known (Kotlin's `NonCancellable` can hang, Java's `StructuredTaskScope.close` waits for ever) — and with its documentation stating that a protected section hides the cancellation from its own caller and must re-check afterwards. ^ncrit-oa64
4. As a kernel maintainer, I want `Tls_flow`, `Rate_limiter`, `Agent`, `Channel` and the IPC registry moved to `Ox.Mutex` where they hold shared state, so that each lock in ox guards a branded datum. ^ncrit-tbq0
5. As a service author, I want two section kinds: `with_access` (`@ local once unyielding`, for short bookkeeping — suspension inside it refused once row 71 lands) and `with_access_waiting ~io` (`yielding`, for sections that legitimately wait, such as a condition wait or a transport write under the lock), so that the 22 general Eio mutex sections in ox and Leash's declared-synchronous `tabs.ml` sections each get the contract they mean (row 75 Findings §3). ^ncrit-9sfw
6. As a kernel maintainer, I want compile-fail cases (no lock, wrong brand, leaked access, write through `@ read` from `read-only-status` where relevant), so that each refusal is pinned. ^ncrit-lpe4

## Implementation Decisions

Verified (ADR-0010): the four refusals above with a 15-line `Guard` over `Eio.Mutex`, branded by an existential. Names follow `Capsule` (`Data`, `Access`, `Key` if a key/unique form is needed) and `Await.Mutex.with_access`. Exceptions inside the section unlock and re-raise; Eio's poisoning on cancellation is kept.

Evidence: [research/01-eio.md](../usage-rules/research/01-eio.md), [research/05-neighbours.md](../usage-rules/research/05-neighbours.md). `Ox.Condition.await` keeps Eio's rule that a condition is waited on with the mutex held and inside a loop re-checking the predicate.

## Out of Scope

Cross-domain locks (`Capsule.Mutex` when a consumer pulls domains); reader–writer locks.