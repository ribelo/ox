---
status: ready-for-agent
package: eta_blocking
consumer: nema row 31 (nemanext-mtpq)
---

# A resource owner learns when a blocking callback has physically finished

## Problem Statement

A caller that times out or is cancelled is released at once, but its native callback keeps running on its thread. nema's Ladybug owner leases a DB connection per call and must not release or reuse it — including after a rollback that runs once the caller gave up — until the callback has physically completed. The callback cannot release it itself: it runs on a system thread and the lease is owned by an Eio domain.

## User Stories

1. As a resource owner, I want `?on_settled:(('a, exn) result -> unit)` on `run`, `try_run`, `run_result`, `try_run_result` and `run_result_timeout`, invoked exactly once in the pool owner's Eio context after the callback has physically completed — whether the caller is still waiting, was cancelled or timed out — so that I release a lease only then. Not invoked for a call cancelled before a worker claimed it (the callback never ran); a raising hook is a defect, as for `on_cancel`. ^nblk-2h3g

## Testing Decisions

- Settled after normal completion; after caller cancellation with the callback still running (hook fires once, after it finishes); after `run_result_timeout`'s timeout; never for a pre-claim cancel; ordering with `Pool.shutdown` Drain.
