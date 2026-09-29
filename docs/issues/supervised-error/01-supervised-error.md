---
status: completed
package: eta (Scope, Concurrent, Retry, Schedule)
consumer: every application; Pie (12 Concurrent sites), Leash drive/run loops, nema watcher
---

# Supervised scopes with application errors, and Concurrent over Eio

## Problem Statement

Typed errors are values, but a value returned by a forked fiber goes nowhere unless the parent joins it, and Eta's `race`/`par`/`all` — written with their own child switches — ignored the caller's cancellation and lost interruption identity (2026-09-28). What v1 had, and direct style so far lacks, is *a typed error in one fork ending the whole concurrent computation*, the way an exception does. Ox solves this with `supervisedError(ErrorMode)`: forks return `Either`, a `Left` ends the scope with that error. Eta needs the same, over Eio's own primitives so that cancellation is Eio's job.

## Solution

`Scope.supervised_error`: a scope whose `fork_error` fibers return `('a, 'e) result`; the first `Error e` ends the scope, cancels and awaits the rest, and the scope returns `Error e`. `Concurrent.race`/`par`/`all`/`for_each` become thin wrappers over `Eio.Fiber.first`/`pair`/`all`/`List.map ~max_fibers`, carrying the typed error through Eio's cancellation, with one law: they raise exactly what the body would raise and return exactly the body's `result`, adding nothing and swallowing nothing. `Retry` gains Ox's result policy and `Schedule` its missing constructors.

## User Stories

1. As a service author, I want `Scope.supervised_error ~sw:_ (fun scope -> …)` returning `('a, 'e) result`, where `Scope.fork_error scope (fun () -> ('b, 'e) result)` starts a supervised fiber whose `Error e` ends the scope with `Error e` after cancelling and awaiting every other fork, so that a typed failure in one fork ends the computation like an exception would. ^nsup-xkke
2. As a service author, I want `Scope.fork scope (fun () -> unit)` (plain, exception-only) usable inside the same scope with its return value not inspected, so that fibers that cannot fail typed do not have to return a result. ^nsup-hm4o
3. As a service author, I want `fork_error` to return a handle whose `await` yields the fork's `result`, so that a fork's typed success can be joined and used within the scope. ^nsup-xzl3
4. As a service author, I want an exception in any fork to end the scope by raising that same exception after the others are cancelled and awaited, with interruptions of the losers suppressed onto it (visible through `Scope.run`'s `Cause`), so that unrecoverable errors keep Ox's semantics: nothing added, nothing swallowed. ^nsup-1lzt
5. As a service author, I want the body's own `Error e` to end the scope the same way a fork's does, so that the scope has one rule regardless of who fails. ^nsup-a4bf
6. As a service author, I want cancellation of the enclosing fiber to cancel the scope and every fork, and `supervised_error` to propagate the cancellation (never turn it into a typed error), so that the scope is an ordinary participant in Eio's structured concurrency. ^nsup-5j80
7. As a service author, I want `Concurrent.par ~sw f g`, `all`, `race`, `both` and `for_each ~concurrency xs f` rewritten over `Eio.Fiber.pair`/`all`/`first`/`both`/`List.map ~max_fibers`, running in the caller's cancellation context, so that cancelling the caller cancels them and no Eta-owned switch stands between the caller and Eio. ^nsup-hd24
8. As a service author, I want each combinator to obey the law "raises exactly what the body raises; returns exactly the body's result; adds nothing; swallows nothing; interruption of losers is suppressed onto the primary", and a property test to check it against exception, typed error, and success in every position, so that the law is enforced rather than described. ^nsup-i1zm
9. As a service author, I want `race` to return the first *success* and, when all branches fail, `Error (Concurrent causes)` in input order, and `race_first` to return the first *settled* result of either kind, so that both Ox race variants exist and are named. ^nsup-zzhl
10. As a service author, I want `Retry.retry ~clock ?policy schedule f` where `policy = { is_success : 'a -> bool; is_worth_retrying : 'e -> bool; on_retry : int -> ('a, 'e) result -> unit }` (Ox's `ResultPolicy` and `onRetry`), defaulting to today's behaviour, so that a successful-looking reply can be retried and a hopeless error can fail fast. ^nsup-pzj6
11. As a service author, I want `Schedule.decorrelated_jitter`, `max_retries_by_cumulative_delay`, `max_interval`, `with_initial_delay`/`with_no_initial_delay`, and `intervals` (explicit list) added, and `jittered` to take Ox's jitter kinds (`Full`, `Equal`, `Decorrelated`), so that the schedule vocabulary matches Ox's. ^nsup-69fi
12. As a service author, I want `Timeout.timeout` to be a documented alias of `Eio.Time.with_timeout` taking a `Duration.t`, and `Resource.acquire_release` removed in favour of `Switch.on_release`, so that Eta does not duplicate Eio. ^nsup-gxmx
13. As a service author, I want the two error kinds written as doctrine in `docs/why-next.md` in Ox's words (unrecoverable → exceptions, untyped on purpose; recoverable → values, made known to combinators through their result type), with the rule that libraries convert I/O exceptions to `result` at their edge and keep `try`/`with` as small as possible, so that the discipline is stated once. ^nsup-o65j
14. As a maintainer, I want Pie's 12 `Concurrent` call sites, Leash's loops and nema's watcher moved to the new combinators or `supervised_error` where they fork typed work, so that the consumers exercise the new scope on the day it lands. ^nsup-6sar
15. As a maintainer, I want the four cancellation regressions of 2026-09-28 (caller cancel ignored, identity lost through daemons, half-frame on cancelled write, exporter losing its queue) kept as tests against the rewritten combinators, so that the rewrite cannot reintroduce them. ^nsup-q444
16. As a maintainer, I want `docs/modes.md` to record that a `handled_effect`-style local token cannot cross `Fiber.fork` because Eio's fork closures are global, that `supervised_error` is the chosen answer, and the one upstream request that would change this (marking `Switch.run`'s body safe for local capture), so that nobody re-opens the search. ^nsup-hje5

## Implementation Decisions

- `supervised_error` is `Switch.run` plus a `Promise` for the first typed error: `fork_error` runs the thunk in `Fiber.fork`, and on `Error e` resolves the promise and calls `Switch.fail sw (Ended_with_error)` with a private exception carrying `e` (typed, generic over `'e` via a locally abstract type or a GADT witness); the scope catches only its own exception at the boundary and returns `Error e`. Exceptions from forks propagate through `Switch.run` untouched. Cancellation propagates untouched.
- Combinators: `par` = `Fiber.pair` with each side's `Error` raised as the private exception inside the pair and caught at the boundary, so Eio does the fail-fast cancel-and-await; `all` likewise over `Fiber.all` or `List.map`; `race` = `Fiber.first` keeping the first `Ok`, collecting `Error`s. No Eta-owned switch except the one `supervised_error` itself is.
- The private exception type is never exposed; `Scope.classify` maps it before any `Cause` is built.
- `Concurrent.with_background` stays (Eio has no direct equivalent) but is reimplemented as `supervised_error` with one `fork_error` for the background and the body in the scope body.
- Retry's policy record is a plain record with defaults; `on_retry` receives the attempt number and the attempt's result.

## Testing Decisions

- Seam: the public modules under `Eio_main` with `Eio_mock.Clock`, exactly as `test/core` today. No new seam.
- Stories 1–6: a table of scopes with forks that succeed / return `Error` / raise / are cancelled from outside, asserting the scope's result, that every fork was awaited (fiber census), and the `Cause` seen by `Scope.run`.
- Stories 7–9: the law as a property test over generated outcome patterns per position; the 2026-09-28 regressions ported (story 15).
- Stories 10–11: mock-clock tests for each policy branch and each new schedule.
- Story 14: the consumers' own suites after their call sites move.

## Out of Scope

Streams (`Flow`), rate limiting, actors (separate specs); effect-row typing; any interpreter.

## Further Notes

Ox's `supervisedError` distinguishes user forks (the scope waits for them) from daemon forks (the scope ends when the body ends); Eio's `fork` vs `fork_daemon` is the same split and is exposed unchanged. Whether `fork_error` should also have a daemon variant is left to the implementer's first consumer.

## Verification

Verified 2026-09-29 on 5.4.0+ox: `nix develop -c dune build @install`, `dune test` (core suite 109 tests, every story cited by name in `test/core/supervised.ml`; the law of story 8 is checked exhaustively over every outcome pattern and settling order for 2–3 branches) and `dune build @fmt` are green. Leash, Pie and nema build and pass their suites against this tree (Leash 29 test cases, Pie 127, nema runtest) through a private install prefix; their edits need the Eta commit installed or re-locked before they compile.

Decisions taken where the spec left room: `Concurrent` combinators keep `~sw` (checked, not owned), including `for_each ~sw ~concurrency`; `par` is built on `Fiber.both` because `Fiber.pair` does not cancel its second side when the first fails (recorded in `docs/modes.md`); a defect in a `race` branch is raised, no longer collected as `Cause.Die`; `Retry.retry`'s schedule takes the attempt's `result` as input so an unsuccessful `Ok` can be retried; `fork_error_daemon` was added for `with_background`, its first consumer; `with_initial_delay` replaces the delay of the first recurrence, not of the first attempt.
