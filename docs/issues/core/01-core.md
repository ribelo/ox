---
status: completed
package: eta
consumer: Leash milestone 1 (chrome-qo4q, chrome-2z2z, chrome-6lfk, chrome-b288, tab-hxld, tab-9x5e, own-uo77)
---

# Core: typed results, Cause and Exit, scopes, and the combinators Eio lacks

## Problem Statement

An application on Eio has exceptions for failure, `Switch` for scope, and `Fiber` for concurrency, but no typed failure channel that composes with those, no precise answer to "what happened to this scope" when several things went wrong at once, and no race/timeout/retry/repeat that report typed outcomes. v1 solved this with an interpreted effect type; eta-next solves it with a small set of direct-style functions over Eio.

## Solution

One package, `eta`, with: a `Result` syntax module; `Duration` and `Schedule` (copied from v1, pure); `Cause` and `Exit`; `Scope.run`, which classifies what came out of a scope into a Cause; and the combinators `race`, `timeout`, `par`, `all`, `with_background`, `acquire_release`, `retry`, `repeat`, each a direct-style function over Eio. Everything takes its Switch and clock explicitly.

## User Stories

1. As a service author, I want `let*` and `let+` over `result` from one `Eta.Result.Syntax`, so that every module composes typed failures the same way. ^ncore-e8jg
2. As a service author, I want `Duration` with millisecond precision and arithmetic, so that timeouts and schedules speak one unit. ^ncore-aqu8
3. As a service author, I want `Schedule` as pure data — `spaced`, `fixed`, `exponential`, `fibonacci`, `linear`, `recurs`, `forever`, `during`, `recur_until`, `jittered`, `both`, `either`, `and_then`, `modify_delay` — stepped with an explicit `now_ms`, so that restart and expiry policies are values I can test without a clock. ^ncore-n04u
4. As a service author, I want a `Cause` type distinguishing typed failure, defect with backtrace, interruption with optional identity, finalizer failure after success, a primary failure with a suppressed finalizer failure, and concurrent causes, so that every failure is fully described. ^ncore-k6az
5. As a service author, I want `Exit` as success-or-Cause with `pp`, `is_interrupt_only`, `to_result` (typed failure only) and `process_code`, so that boundaries render and map outcomes uniformly. ^ncore-4hth
6. As a service author, I want `Scope.run f` to own a Switch, pass it to `f`, and return an `Exit` where a returned `Error` is `Fail`, an escaped exception is `Die` with its backtrace, `Eio.Cancel.Cancelled` is `Interrupt` with the identity when it carries one, and a failing `Switch.on_release` is `Finalizer` (or `Suppressed` under a primary failure), so that classification is done once, at the boundary. ^ncore-3ry6
7. As a service author, I want interruptions requested by Eta's own combinators to carry a private identity, so that `Scope` and `with_background` can tell "we stopped it" from "someone cancelled us". ^ncore-5caq
8. As a service author, I want `timeout ~clock d f` to fail with ``Timeout`` after `d` and to cancel and await `f` before returning, so that a timed-out body never runs on after the deadline. ^ncore-7n2j
9. As a service author, I want `race ~sw fs` to return `('a, 'e Cause.t) result`: the first *success* wins, losers are cancelled and awaited, and when all fail the error is `Concurrent` of their causes in input order — the bare cause when only one branch failed — so that a race failure composes with my own error union and deadlines are never expressed as a race against a sleep. ^ncore-7vo9
10. As a service author, I want `par ~sw f g` and `all ~sw fs` to run concurrently, fail fast (a failing side cancels the rest and everything is awaited), and return the pair or list on success, so that fan-out has one semantics. ^ncore-a6g1
11. As a service author, I want `with_background ~sw bg body` to run `bg` alongside `body`, cancel and await `bg` when `body` settles, let a `bg` failure that comes first cancel `body` and win, and never report Eta's own stop of `bg` as a failure of `body`, so that an essential reader has one owner. ^ncore-gpuq
12. As a service author, I want `acquire_release ~sw ~acquire ~release` to register `release` on the Switch, run it on every exit, and report its failure as `Finalizer` or `Suppressed`, so that resources are owned by scopes. ^ncore-zpe1
13. As a service author, I want `retry ~clock schedule f` to rerun `f` on `Error` according to the schedule, sleeping on the given clock, and return the last error when the schedule stops, so that transient failures are handled by policy. ^ncore-zda1
14. As a service author, I want `repeat ~clock schedule f` to rerun `f` after each `Ok` according to the schedule and return the schedule's output when it stops or `f`'s error when it fails, so that periodic work is a policy plus a thunk. ^ncore-2isd
15. As a service author, I want cancellation during a `retry`/`repeat` sleep to interrupt promptly, so that a stopping service does not wait out a backoff. ^ncore-rzml
16. As a service author, I want `Interrupt_id` values comparable and printable, so that traces can say which combinator stopped what. ^ncore-5dj2
17. As a service author, I want every combinator to take its Switch and clock as explicit arguments and never read ambient state, so that a signature says what a function can do. ^ncore-5zbb
18. As a service author, I want no function in `eta` to catch an exception it does not classify into a Cause, so that defects are never silently converted into typed failures. ^ncore-mvvi
19. As a test author, I want all sleeping in `timeout`, `retry` and `repeat` to go through the clock argument, so that `Eio_mock.Clock` makes them deterministic. ^ncore-acna
20. As a service author, I want `Cause.pp` to render nested causes readably with the typed payload printed by a supplied printer, so that a journal line is enough to understand a failure. ^ncore-30fk
21. As a service author, I want `Exit.to_result` to return `Error e` only for a bare `Fail e` and to expose everything else as the Cause, so that no boundary can accidentally treat a defect as a handled error. ^ncore-p30f
22. As a kernel maintainer, I want the package to depend on `eio` and the standard library only, so that the dependency policy holds at the root. ^ncore-kyk3
23. As a kernel maintainer, I want every public module to have a `.mli` with doc comments stating the cancellation and finalizer behaviour, so that the semantics are the contract. ^ncore-161o
24. As a kernel maintainer, I want the v1 `Schedule` and `Duration` tests copied with the code, so that the pure parts keep their proven behaviour. ^ncore-fjud

## Implementation Decisions

- Package `eta`, library `eta`, modules: `Result` (syntax only), `Duration`, `Schedule`, `Interrupt_id`, `Cause`, `Exit`, `Scope`, `Concurrent` (race, par, all, with_background), `Timeout`, `Resource` (acquire_release), `Retry` (retry, repeat). Module names are a proposal; one public module `Eta` re-exports them.
- `Duration` and `Schedule` are copied from v1 (`git show v1:lib/eta/duration.ml`, `schedule.ml`, their `.mli` and tests) with mode annotations removed unless they earn a guarantee; `Schedule.step` already takes `now_ms`.
- Cause is the shape in `docs/why-next.md` §4; no other variants.
- Interruption identity: each combinator that cancels creates a fresh `Interrupt_id` and cancels with a private exception carrying it; `Scope.run` maps `Eio.Cancel.Cancelled (That_exn id)` to `Interrupt (Some id)` and any other `Cancelled` to `Interrupt None`.
- `race` implements first-success by running each thunk in its own fiber under a child Switch, resolving a Promise on the first `Ok`, then failing the child Switch with the private stop exception; it must await all fibers before returning.
- `timeout` is built on `Eio.Time.with_timeout`-style cancellation using the supplied clock, not on `race`.
- `with_background` fails-fast in both directions exactly as v1's contract (`v1:lib/eta/effect.mli.in` lines 745–752) but implemented with a child Switch and two fibers; the linearization rule (first terminal publication wins) is kept.
- Thunks everywhere: `unit -> ('a, 'e) result`. No `Effect.t`, no runtime, no interpreter.
- OxCaml: annotate closures `@ local` where they do not escape (combinator arguments) once the toolchain's Eio signatures allow it; do not add `portable` to this package.

## Testing Decisions

- Tests under `test/core/`, Alcotest, run under `Eio_main.run` with `Eio_mock.Clock` where time matters. Each test names the story IDs it covers in its name.
- Classification: `Scope.run` on a body that returns Error, raises, is cancelled externally, is cancelled by a combinator, has a failing on_release after success, has a failing on_release after failure — ncore-k6az, ncore-3ry6, ncore-5caq, ncore-p30f.
- Combinators: winner/loser behaviour, all-fail, cancellation awaited, background stop not reported — ncore-7n2j, ncore-7vo9, ncore-a6g1, ncore-gpuq, ncore-zpe1, ncore-rzml.
- Schedules with a mock clock, asserting virtual time advanced — ncore-n04u, ncore-zda1, ncore-2isd, ncore-acna.
- A fiber census after each concurrent test (no fiber still running) — ncore-mvvi.
- Copied v1 tests for Duration/Schedule — ncore-fjud.

## Out of Scope

Streams, queues, semaphores, pools, pubsub (Eio has `Stream`, `Semaphore`, `Mutex`; add only when a consumer story needs more); observability hooks; any capability record.

## Further Notes

- The handled-effect spike (`.scratch/research/handled-pattern/`) may later change the error channel; this spec assumes `result` per ADR-0002.
- The flake's package list must be updated as this package appears (see `docs/issues/README.md` row 0).
- Story ^ncore-7vo9's `race` failure shape is superseded by `docs/issues/review-fixes-1/01-review-fixes-1.md` (^nfix-yrjy): `race` returns `('a, 'e Cause.t) result` and no longer wraps failures in a `Concurrent` variant.

Verification: `nix develop -c dune build @install` and `nix develop -c dune test test/core` pass (62 tests; all 24 story IDs).
Whole-tree `nix develop -c dune test` awaits schema worker’s `Yojson` test fix; integration lead will rerun it.
