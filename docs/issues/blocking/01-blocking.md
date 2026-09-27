---
status: completed
package: eta_blocking
consumer: nema (vault native reads and database), grip (linux_input device reads)
---

# Blocking: bounded native calls without blocking Eio fibers

## Problem Statement

Nema runs synchronous vault/database work while its Eio scheduler remains responsive, limits simultaneous native calls, refuses overload for some reads, and must not reuse resources before a cancelled call physically ends. Grip holds a descriptor lease across a blocking device read and requires drain-on-shutdown. Eio_unix.run_in_systhread alone creates another worker when all workers are busy; it provides no service-level admission budget.

## Solution

A small direct-style `eta_blocking` package wraps Eio_unix.run_in_systhread behind a per-service bounded pool. Waiting calls may enter a bounded queue; fail-fast calls refuse saturation. Cancellation releases the caller promptly but does not interrupt an already running native callback: the callback retains its worker slot until it physically returns. A cooperative on_cancel hook lets a consumer signal its own callback. Shutdown either drains physical calls or detaches them, explicitly selected at creation.

## User Stories

1. As nema's service author, I want one named pool with bounded active calls and queued admissions, so that database and vault calls have a service-level native concurrency budget. ^nblock-a7q2
2. As nema's vault author, I want a fail-fast result-returning call with typed saturation/shutdown outcomes, so that an overloaded read never silently waits and its domain error stays typed. ^nblock-f4kx
3. As nema's vault author, I want a timeout and cooperative cancellation hook that release the caller but keep the physical slot occupied, so that a slow native read cannot be mistaken for completed work. ^nblock-j9wr
4. As grip's device author, I want result-returning blocking reads and a draining shutdown, so that a descriptor lease is not released before a native read physically ends. ^nblock-p5dm
5. As a service author, I want cancellation before worker start to prevent callback execution, and cancellation after start to invoke the hook at most once, so that resource ownership is unambiguous. ^nblock-v8ze

## Implementation Decisions

- Pool.create requires an owner Eio.Switch.t. Every native call runs in a separate worker fiber attached to that switch, because Eio_unix.run_in_systhread itself does not release a suspended caller promptly on timeout. The pool owns a worker-slot semaphore and a bounded admission queue; callbacks run only inside Eio_unix.run_in_systhread. Additional callers wait outside admission; try_run variants never queue. max_threads must be positive and max_queued nonnegative. Shutdown before the owner switch ends.
- run/run_result wait for capacity; try_run/try_run_result return Not_run Saturated or Shutting_down without scheduling. Domain callback errors remain typed as `Error (`Callback error)`; pool failures have distinct typed variants. Callback exceptions propagate as defects without conversion.
- A per-call atomic claim decides whether the worker starts or the caller cancels before it starts. The physical callback releases the slot, even after the caller was released; cancellation signals on_cancel at most once only after worker claim. The hook is cooperative and does not forcibly terminate a worker.
- Timeouts bound only caller wait. Draining shutdown stops admission and waits for physical work; Detach_started stops admission without waiting, and is unsafe for callbacks borrowing resources released on return from shutdown. No ambient runtime/default pool and no eta_par; callers explicitly pass a pool.

## Testing Decisions

- Native systhread success/result/error/exception, active limit, queue saturation, and shutdown outcomes: nblock-a7q2, nblock-f4kx, nblock-p5dm.
- Gates synchronized by thread-safe semaphores, not timing guesses: cancel before claim, cancel during execution, timeout, slot retention and hook count, draining shutdown: nblock-j9wr, nblock-v8ze, nblock-p5dm.

## Out of Scope

Domain parallelism (eta_par), v1's ambient runtime/default pool, portable-capsule adapters, callback preemption, and migration of either consumer repository.

Verification: `dune build eta_blocking.install` and `dune test test/blocking` passed (five story-linked tests).
Formatting: `ocamlformat --check` passed for all three owned OCaml files; full-tree gates belong to integration while sibling rows are in progress.
