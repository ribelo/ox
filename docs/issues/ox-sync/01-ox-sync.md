---
status: ready
package: ox
consumer: Ox (ADR-0010)
---

# Synchronization primitives at least as safe as `await`'s

## Problem Statement

Eio's primitives are correct at run time and say nothing at compile time. Compared on 2026-10-04 with Jane Street's `await` (`sync/*.mli`, branch `oxcaml`) and against what OxCaml can refuse:

| Eio | Gap | `await` | Ox can do |
|---|---|---|---|
| `Promise.resolve` | resolving twice raises at run time | `Ivar.fill_exn`, same | a `unique` resolver consumed by `resolve`: a second resolve does not compile |
| `Semaphore.release` | any fiber releases any number of times; no poisoning | poisoning, `acquire_or_cancel` | `acquire` returns a `Permit.t @ unique` that `release` consumes: release without acquire, or twice, does not compile; poisoning |
| `Stream` (and `Ox.Channel`) | every holder can add and take; values are shared | `Mvar` moves `once unique` values; `Bounded_spsc_queue` hands out unique producer and consumer ends | send and receive ends; single-producer/single-consumer ends `unique`; an owned channel whose `send` takes `'a @ unique` and `receive` returns it `unique` |
| `Condition.await_no_mutex` | waiting without the guarding lock loses wake-ups | condition bound to a capsule mutex | `Ox.Condition.await` requires the `'k Access.t` of the `Ox.Mutex` (row 65) that guards the predicate |

`Eio.Lazy` (cancellation behaviour chosen at creation) and `Eio.Executor_pool` (wrapped by row 80) were checked and are not replaced. `Barrier` and `Countdown_latch` do not exist in Eio; they are added in `await`'s shape because `await` has them and they are refusable the same way.

## Solution

`Ox.Promise`, `Ox.Semaphore`, `Ox.Channel` ends and `Ox.Channel.Owned`, `Ox.Condition`, `Ox.Barrier`, `Ox.Countdown_latch`, over Eio, with `once-forks`' `Ox.Once` for the casts, names after `await`, and the `raw-concurrency-gate` refusing the Eio originals outside `lib/ox`.

## User Stories

1. As a service author, I want `Ox.Promise.create : unit -> 'a t * 'a resolver @ unique` and `resolve : 'a resolver @ unique -> 'a -> unit`, so that resolving twice does not compile. ^nsync-b0f7
2. As a service author, I want `Ox.Semaphore.acquire : t -> Permit.t @ unique` and `release : t -> Permit.t @ unique -> unit`, `with_permit : t -> (unit -> 'a) @ local once -> 'a`, and `poison`, so that a permit cannot be released twice or forged. ^nsync-mxc5
3. As a service author, I want `Ox.Channel.split : ('a, 'e) t -> 'a sender * 'a receiver` for many-to-many use and `Ox.Channel.spsc : capacity -> 'a sender @ unique * 'a receiver @ unique` for single-producer/single-consumer, so that the shape of a channel's use is in its type. ^nsync-as20
4. As a service author, I want `Ox.Channel.Owned` whose `send` takes `'a @ unique` and whose `receive` returns `'a @ unique`, so that an owned handle (row 62) can be moved between fibers through a channel without an alias staying behind. ^nsync-73n9
5. As a service author, I want `Ox.Condition.await : t -> 'k Ox.Mutex.Access.t @ local -> unit` and no mutex-free wait, so that a condition cannot be waited on without the lock that guards its predicate. ^nsync-p4s4
6. As a service author, I want `Ox.Barrier` and `Ox.Countdown_latch` in `await`'s shape (`create`, `await`, `poison`), so that a phase barrier is not rebuilt from a counter and a condition. ^nsync-xozj
7. As a kernel maintainer, I want every blocking operation here to have the shape `cancellation-value` (row 73) decides — today Eio's cancellation, later `_or_cancel` returning `Canceled` if the ADR adopts it — so that the sync layer does not fix the cancellation model early. ^nsync-m9c6
8. As a kernel maintainer, I want compile-fail cases for stories 1–5 and `@stress` cancel storms over each primitive, so that the refusals and the run-time behaviour are both pinned. ^nsync-xmpn
9. As a kernel maintainer, I want `raw-concurrency-gate` (row 66) extended to `Eio.Promise`, `Eio.Semaphore`, `Eio.Stream` and `Eio.Condition` outside `lib/ox`, so that the safer versions are the only ones. ^nsync-ubw8

## Implementation Decisions

Verified patterns (ADR-0010): consuming a `unique` value twice is refused; branded access is refused without the lock. The owned channel stores elements `@@ aliased` internally and restores uniqueness with the audited `Ox.Once`-style cast on receive, justified because the queue is the only holder.

## Out of Scope

Cross-domain primitives (row 80 uses Eio's executor pool and `portable` values).
