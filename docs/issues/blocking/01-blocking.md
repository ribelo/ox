---
status: ready-for-agent
package: ox_blocking
consumer: Exergy SQLite ingestion; existing native workers
priority: P1
---

# Cancellation-safe shared blocking-pool drain

## Problem Statement

Pool Drain currently takes every worker-slot permit sequentially without shared shutdown state. Two drain callers can each retain some permits and wait forever for the others. Cancelling a drain after partial acquisition leaks those permits and can strand later cleanup. Exergy must drain native database work before dependent telemetry/resources are released.

## Solution

Make Drain one linearizable shared ending that seals admission and settles physically started callbacks and their settled hooks. Concurrent/repeated callers join that ending without splitting slot ownership; interruption of a waiter does not corrupt the pool or abandon native settlement.

## User Stories

1. As nema's service author, I want one named pool with bounded active calls and queued admissions, so that database and vault calls have a service-level native concurrency budget. ^nblock-a7q2
2. As nema's vault author, I want a fail-fast result-returning call with typed saturation/shutdown outcomes, so that an overloaded read never silently waits and its domain error stays typed. ^nblock-f4kx
3. As nema's vault author, I want a timeout and cooperative cancellation hook that release the caller but keep the physical slot occupied, so that a slow native read cannot be mistaken for completed work. ^nblock-j9wr
4. As grip's device author, I want result-returning blocking reads and a draining shutdown, so that a descriptor lease is not released before a native read physically ends. ^nblock-p5dm
5. As a service author, I want cancellation before worker start to prevent callback execution, and cancellation after start to invoke the hook at most once, so that resource ownership is unambiguous. ^nblock-v8ze
6. As a session author, I want two concurrent Drain calls to join one drain, so that they cannot each retain part of the worker budget and deadlock. ^nblock-5siy
7. As a session author, I want cancellation of a Drain waiter to leave a drain that another caller can finish, so that cleanup does not leak partially acquired reservations. ^nblock-8z91
8. As a service author, I want repeated Drain after completion to return promptly without changing accounting, so that release paths are idempotent. ^nblock-de0p
9. As a service author, I want shutdown to seal admission once and reject queued/new work honestly without starting callbacks, so that no work slips in after the ending begins. ^nblock-l36w
10. As a resource owner, I want successful Drain only after every started callback physically returns and its on_settled hook completes exactly once, so that native leases are released safely. ^nblock-faq7
11. As a service author, I want callback values, callback exceptions and waiter cancellation to preserve the existing typed-result/defect contract, so that the drain fix does not convert or swallow failures. ^nblock-qwwp
12. As a switch owner, I want owner-scope cancellation tested with started native workers, so that its join and settled-hook lifetime are distinguished from a caller-only timeout or cancellation. ^nblock-c664
13. As a test author, I want deterministic two-worker/two-drainer and cancelled-drainer fixtures plus saturation/admission regression tests, so that deadlocks are reproduced without relying on sleeps. ^nblock-vm4e

14. As a resource owner of a Drain-configured pool, I want a settled-hook defect after caller cancellation retained and raised by every Drain with its original backtrace, so that abandoned cleanup failure cannot be lost. ^nblock-l78q

## Implementation Decisions

- Keep explicit pool ownership and the current bounded native-worker execution boundary. Shutdown must occur before the owning switch ends while callback dependencies are still valid.
- Use one shared drain/completion state, not independent acquisition of the whole semaphore budget. Waiters may be cancelled independently; pool-owned settlement must not retain leaked permits or be owned only by the first waiter.
- Drain waits for physical completion, including on_settled. Detach_started remains a distinct pool shutdown policy; it does not promise native threads outlive the enclosing Eio switch. Never free a live SQLite handle merely because the caller stopped waiting.
- Preserve max_threads/max_queued meaning, saturation and Shutting_down results, pre-start cancellation and at-most-once on_cancel. There is no new scheduler or implicit global pool.
- A settled-hook exception remains a defect. Deliberately strengthen the previous lost-if-no-waiter policy: in a Drain-configured pool retain the first observed hook exception and its original backtrace for the pool lifetime. A waiting caller still observes the existing hook outcome; after all physical callbacks/hooks settle, every concurrent or repeated Drain raises the same retained defect instead of reporting success. Shutdown policy remains fixed at creation. Detach_started-configured pools keep the documented delivery to a live waiter without a guaranteed observer after abandonment; no transition from Detach_started to Drain or policy override is introduced. No expected SQLite/provider error is invented and no automatic owner-switch failure is introduced.

## Testing Decisions

- Confirmed public seam: real blocking calls and cancellation fixtures, with explicit callback gates and settled-hook latches; no internal semaphore assertions are required.
- With two active workers and two drain callers, release callbacks one at a time so each historical drain would acquire a different permit; both callers must finish only after both physical completions. Outer timeouts detect a regression.
- Cancel a drain after one callback completes while the other remains gated, then invoke a surviving drain; prove it finishes after the remaining callback and all hooks. Repeat shutdown after completion.
- Test queued/new rejection, pre-claim cancellation, typed callback errors, raised callback defects, on_settled once and before successful Drain, and owner-switch cancellation joining physical completion. Preserve existing Detach_started and caller-timeout coverage.
- Cancel a caller after its native worker starts, then let on_settled raise after physical return. Two concurrent Drains and a repeated Drain must settle and raise the same retained defect with original backtrace; none reports successful drain. Cover a still-waiting caller in the same Drain-configured policy. Detach_started is a separate pool policy, not a precursor to Drain; preserve its existing physical-completion and hook execution coverage without promising abandoned-defect reporting.
- Use the existing settled-hook capability as a dependency, not a duplicate implementation: ^nblk-2h3g. The new retained-defect contract replaces its documented loss when nobody waits. Record coverage with the new story IDs.

## Out of Scope

Automatic Pool.create finalizers, forcefully killing OS threads, retry, SQLite transaction policy, cancellation making COMMIT reversible, and changing Detach_started into detached process lifetime.

## Further Notes

- Audit 2026-10-04. Relevant source is unchanged between Ox 08c6fc8f and 72af4cde. The deadlock is a source-level interleaving; no new compiled Ox reproducer was run during this read-only audit.
- Evidence: [pool state/create:15–50](<../../../lib/blocking/ox_blocking.ml#L15-L50>), [Drain:65–77](<../../../lib/blocking/ox_blocking.ml#L65-L77>), [shutdown contract](<../../../lib/blocking/ox_blocking.mli>), and [current blocking tests](<../../../test/blocking/run.ml>).
- No automatic-drain gap is claimed: the original capability explicitly requires shutdown before the owner switch ends. Exergy must register its protected explicit cleanup in that order.
- Already delivered: [settled hook capability](<../blocking-settled/01-blocking-settled.md>). Its physical-settlement guarantee remains independent of caller timeout/cancellation.
