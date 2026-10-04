---
status: completed
package: ox (RateLimiter, Select), ox_app (OxApp parity), docs
consumer: Leash (rate limiting model calls per site; select over CDP events), Pie, nema
---

# The rest of Ox's floor: rate limiter, select, resources, app, and the Flow design

## Problem Statement

ADR-0009 says everything on Ox's floor exists in Ox. After `supervised-error`, the missing items are: a rate limiter, `select` over channels, the resource-scope helpers in Ox's shape, a check of the Door against `OxApp`, and streams. Streams are the largest gap and the one to design from Ox's `Flow` before any application pulls them, so that the first stream code is not written in a hurry.

## Solution

Add `RateLimiter` and `Select` as small modules over Eio primitives; align resource helpers and the Door with Ox's naming where it costs nothing; and write the `Flow` design (types and operator list, no implementation) as a design note that a later spec turns into code when the first application needs a stream.

## User Stories

1. As a service author, I want `Rate_limiter.create ~sw ~clock (Fixed_window {n; per}) | Sliding_window {…} | Token_bucket {…}` and `Rate_limiter.run limiter f` blocking until a permit is available, plus `run_or_drop`, so that model calls and site requests can be limited per site the way Ox's `RateLimiter.runBlocking` does. ^nfloor-p4ae
2. As a service author, I want the limiter's algorithm to be a small interface so a custom one can be supplied, so that Ox's 'custom rate limiter algorithms' is possible. ^nfloor-ygtz
3. As a service author, I want `Select.receive [source_clause a; source_clause b]` and `Select.select [send_clause c v; receive_clause d]` over `Eio.Stream`s with an optional default clause and a timeout clause, returning which clause fired, so that a fiber can wait on several channels the way Ox and Go do. ^nfloor-6qf5
4. As a service author, I want a closed stream to be a typed outcome of `select` (`Done` / `Error`), never an exception, so that shutdown of one channel is ordinary control flow. ^nfloor-lchb
5. As a service author, I want `Resource.use_in_scope ~sw acquire release` (value returned, release on `Switch.on_release`) and `Resource.use_closeable_in_scope` for values with a `close`, so that Ox's resource helpers exist by name without duplicating `Switch`. ^nfloor-elwp
6. As an operator, I want the Door checked against Ox's `OxApp`: `run args` returning an exit code, background forks in the app's own scope, SIGINT/SIGTERM as a clean stop, and an `OxApp.Simple`-style variant for programs with no config, so that every item of `OxApp` has a Door counterpart or a recorded reason not to. ^nfloor-6n2e
7. As a service author, I want `Duration` to interoperate with Eio's float seconds through `to_seconds`/`of_seconds` and to be accepted by every Ox function that sleeps or times out, so that there is one time type at Ox's surface and Eio's underneath. ^nfloor-twpq
8. As a maintainer, I want a design note `docs/design/flow.md` specifying `Flow` after Ox's: a lazy description `('a) t` run by `run_foreach`/`run_to_list`/`run_drain`/`run_fold`; sources (`of_list`, `of_seq`, `iterate`, `tick`, `using_emit`, `of_channel`, `of_flow` for byte flows, `lines_utf8`); transformers (`map`, `filter`, `take`, `drop`, `map_stateful`, `intersperse`, `grouped`, `grouped_within`, `buffer`, `throttle`, `merge`, `zip`, `interleave`, `map_par ~concurrency`, `map_par_unordered`, `tap`, `on_complete`); backpressure via `Eio.Stream` capacity; error propagation ending the run with the first failure and cancelling siblings; interop with `Eio.Flow` for bytes and with channels — so that when an application first needs a stream the design is already made. ^nfloor-pjnk
9. As a maintainer, I want the design note to state which operators fork fibers (`merge`, `buffer`, `map_par`, `tick`) and which run in the caller's fiber, and that a `Flow` never starts work until run, so that its concurrency cost is legible. ^nfloor-idvp
10. As a maintainer, I want the design note to decide `Flow`'s error type: `('a, 'e) t` carrying a typed error through `run_*` as `result`, with exceptions propagating as Ox does, so that streams follow the two-error-kinds doctrine. ^nfloor-t8w5
11. As a maintainer, I want the note to name the first likely consumers (Leash's CDP event stream, `run`'s JSONL output, Pie's audio pipeline) and what each would need, so that the first implementation is sized by real use. ^nfloor-tv7b
12. As a maintainer, I want Ox's table of contents pasted into `docs/design/ox-floor.md` with each item marked `have (module)`, `spec (row)`, `design (flow.md)` or `rejected (reason)`, so that 'everything on the floor' is checkable. ^nfloor-37ic
13. As a maintainer, I want `docs/why-ox.md` and `GLOSSARY.md` updated: Ox named as the floor, `Flow`, `Rate limiter`, `Select` added to the vocabulary, and the retired word list unchanged, so that the documents match ADR-0009. ^nfloor-igt7
14. As a maintainer, I want the `leash` and any future consumer skills to mention `Rate_limiter` for per-site model and request limits, so that the first consumer uses it rather than a sleep. ^nfloor-8qx2
15. As a resource owner, I want `Resource.use_in_scope` to release an acquired resource exactly once when its switch has already finished, including cancellation during acquisition, and preserve Eio's registration error, so that a failed registration cannot double-close a resource or replace the caller's failure. ^nfloor-once

## Implementation Decisions

- `Rate_limiter` state is a mutex-guarded record with the clock injected; `run` sleeps on the clock until the algorithm grants; algorithms are a record of `try_acquire : now -> (bool * wait)`.
- `Select` is built on `Eio.Stream.take_nonblocking`/`add` with a `Condition`-driven wait; fairness is round-robin over clauses; the implementation may be replaced by Eio's own `Fiber.first` over clause waiters if that proves simpler.
- `Flow` is design-only in this row; no code.
- ^nfloor-once: Eio owns the registration handoff: `Switch.on_release` either registers the release or runs it immediately under cancellation protection before raising for a finished switch. Ox must not retry release after that exception; the public resource-helper signatures and typed outcomes are unchanged.

## Testing Decisions

- Seam: public modules under `Eio_main` with `Eio_mock.Clock` (`test/core`). Rate limiter: mock-clock tests per algorithm and for `run_or_drop`. Select: closed, default, timeout and fairness cases. Resource helpers: release order and release-on-failure. Door: a checklist test per `OxApp` item.
- ^nfloor-once: use an already-finished switch, count acquisition and release, and assert the unchanged `Invalid_argument "Switch finished!"`. Repeat with cancellation requested inside acquisition; the non-suspending release checks its current cancellation context to prove Eio shields it and still runs it only once.

## Out of Scope

Implementing `Flow` (a later spec when pulled); actors (own spec); reactive-streams interop.

## Verification

Verified 2026-09-29 on 5.4.0+ox: `dune build @install`, `dune test` (the `Ox floor` cases in `test/core/floor_tests.ml` and the OxApp checklist in `test/app/oxapp.ml`), and `dune build @fmt` pass. inn builds and passes its 45 integration tests against a private Ox install (`dune install --prefix /tmp/ox-row46`).

Decisions taken where the spec left room: `Ox.Channel` (bounded, closable, capacity ≥ 1) was added because `Eio.Stream` has no close and story 4 needs one; `Select` clauses carry a handler, so “which clause fired” is what the handlers return, and a closed channel reaches the handler as `Error `Done`/`Error (`Error e)`; `Rate_limiter` has no background fork (permits are computed on demand from the clock), so `~sw` is only checked, as in `Concurrent`; `Custom` takes a factory (`now_ms:int -> algorithm`); `Resource.use_closeable_in_scope` closes with `Eio.Resource.close`; `Ox_app.run_simple`, `Config.none`, and `?exit_code` on `run`/`run_for_test` complete the OxApp mapping; `ox_sql` pool timeouts became `Duration.t` (story 7; inn’s three call sites moved). Story 14 was intentionally not done in the `leash` skill: that skill is an operator’s guide to the Leash CLI, not Ox API guidance; `docs/design/ox-floor.md` carries the guidance instead.
