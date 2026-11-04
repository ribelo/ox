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

1. As a service author, I want `Ox.Mutex.create : unit -> packed` (`P : 'k t -> packed`), `with_access : 'k t -> ('k Access.t @ local -> 'b) @ local once unyielding -> 'b`, and opaque owner operations requiring the matching access, so that ordinary consumers cannot access the owner's guarded state without its lock. Mutable state is allocated inside the owner; a generic payload constructor or getter is not an ownership boundary. ^ncrit-ihf2
2. As a service author, I want data of one mutex's brand refused with another mutex's access, and the access refused outside the critical section, so that the lock that guards a datum is part of its type. ^ncrit-1px5
3. As a service author, I want `Ox.Cancel.protect : ?deadline:(Mono clock * Duration.t) -> (unit -> 'a) @ local once -> 'a` over `Eio.Cancel.protect` — with the deadline because Trio's shielded cleanup takes one and the failure modes on either side are known (Kotlin's `NonCancellable` can hang, Java's `StructuredTaskScope.close` waits for ever) — and with its documentation stating that a protected section hides the cancellation from its own caller and must re-check afterwards. ^ncrit-oa64
4. As a kernel maintainer, I want `Tls_flow`, `Rate_limiter`, `Agent`, `Channel` and the IPC registry moved to `Ox.Mutex` where they hold shared state, so that each lock in ox guards a branded datum. ^ncrit-tbq0
5. As a service author, I want two section kinds: `with_access` (`@ local once unyielding`, for short bookkeeping — suspension inside it refused once row 71 lands) and `with_access_waiting ~io` (`yielding`, for sections that legitimately wait, such as a condition wait or a transport write under the lock), so that the 22 general Eio mutex sections in ox and Leash's declared-synchronous `tabs.ml` sections each get the contract they mean (row 75 Findings §3). ^ncrit-9sfw
6. As a kernel maintainer, I want compile-fail cases (no lock, wrong brand, leaked access, write through `@ read` from `read-only-status` where relevant), so that each refusal is pinned. ^ncrit-lpe4

## Progress

2026-11-03: stories 1, 2, 5 and 6 delivered (`lib/ox/mutex.mli`, `test/core/ox_mutex`). `with_access_waiting` takes no `~io` yet; the suspension token comes with row 71 (`suspend-token`), and until then `unyielding` refuses captured yielding values but not a raw Eio wait. Story 4 started: `Tls_flow` is an owner (row 63), with `with_access_protected` (shielded acquisition) and `try_with_access_waiting` (non-blocking acquisition) added for its feed and flush paths. Open: story 3 (`Ox.Cancel.protect` needs a collector-safe local bridge into `Eio.Cancel.protect`; see Implementation Decisions) and the rest of story 4 (`Rate_limiter` keeps its protected RW poisoning, so it needs a poisoning section kind; `Agent` and `Channel` get no lock; the IPC registry's cross-domain lock stays until its domain use is verified).

2026-11-04: story 4 restated. `Rate_limiter`'s lock has one call site and guards state that lives in the algorithm's closures, not in a record Ox could brand, so a brand there refuses nothing new; it keeps `Eio.Mutex.use_rw ~protect:true` (^ncrit-tbq0). `Agent` and `Channel` keep no lock, and the IPC registry keeps its Stdlib lock, as above. Story 4 is therefore `Tls_flow` alone. Story 3 stays open: the global-once route through `Ox.Once.guard` would work today, but the result of an expired `?deadline` (raise, or a `result`) is an API choice still to make, and the local-once form needs the collector-safe bridge.

## Implementation Decisions

The brand/access refusals do not prove payload ownership. A retained alias, a mutable-field projection, or a `global`/`aliased` field can escape a generic getter even with a unique outer input and a local view. Guarded owners therefore allocate state internally and export operations rather than raw mutable projections. Their native/Eio providers remain explicit audited boundaries; custom limiter callbacks remain borrowed extensions, not exclusively owned captures.

Preserve each caller's actual locking contract: TLS keeps separate locks, nonblocking acquisition and unlock-on-error behaviour; the limiter keeps native protected RW poisoning. Do not add locks to owner-fiber Agent/Channel state. The process-global IPC registry needs an opaque operation boundary without silently replacing a cross-domain Stdlib lock with a single-domain Eio lock. Its domain compatibility must be verified before claiming that migration.

Local-once cancellation and protected RW callbacks require a collector-safe implementation, not merely a joined callback lifetime. Erasing locality and retaining the callback in a heap guard does not root its local capture graph while mutex acquisition waits; that proposed Once bridge is not admitted. The global-once adapter is a separate deliverable and does not establish these local contracts. No generic locality conversion or arbitrary legacy callback runner is public. A Mono deadline must run inside the outer cancellation shield; nested shielding or a non-cancellable provider may still prevent termination. Suspension refusal remains conditional on the actual suspension-token delivery, not merely the callback annotation (safe-fr73).

Evidence: [research/01-eio.md](../usage-rules/research/01-eio.md), [research/05-neighbours.md](../usage-rules/research/05-neighbours.md). `Ox.Condition.await` keeps Eio's rule that a condition is waited on with the mutex held and inside a loop re-checking the predicate.

## Out of Scope

Cross-domain locks (`Capsule.Mutex` when a consumer pulls domains); reader–writer locks.