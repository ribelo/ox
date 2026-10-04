---
status: ready
package: ox_lint (rules), ox, ox_http, ox_otel, ox_ipc, ox_sql
consumer: Ox and every consumer (row 66 moved onto our own decider)
---

# The concurrency rules, decided by `ox-lint`

## Problem Statement

Row 66 specifies the rules that cannot be types — catch-all handlers, suspending finalizers, raw Eio concurrency, Stdlib mutexes, discarded `result`s, public exceptions, `Obj.magic` — and assumed Semgrep would decide them. The spike of row 87 showed what that costs: Semgrep resolves no `open`, has no types, and cannot parse the four ox files with the most interesting modes, while `ox-lint` decided the discarded-`result` rule exactly (8 real sites out of 40 name-level candidates). The rules belong on the decider that can see paths and types.

## Solution

Row 66's rules implemented as `ox-lint` rules, each in the strongest form the tier allows, with their fixtures, their pages, and the existing violations in `lib/` fixed or allow-listed in the same row.

## User Stories

1. As a reviewer, I want `ox-catch-all` in its two decidable shapes — a handler binding the cancellation whose body does not re-raise it first, and a bare `with _ ->` / `with exn ->` that does not re-raise the bound value — with the exception resolved by **origin**, not by name (row 87 proved same-unit rebinding is matched and cross-unit is not, which the page states), and the five existing sites in `lib/` fixed. ^nlintc-du4v
2. As a reviewer, I want `ox-suspending-finalizer`: a suspending call inside a `Fun.protect ~finally`, a `Switch.on_release` callback or an `Ox.Cancel.protect` body, with the suspending set resolved through aliases and `open` by path, and the 33 `Fun.protect` sites in `lib/` each classified, fixed or allow-listed with a reason. ^nlintc-g6k3
3. As a reviewer, I want `ox-raw-concurrency` and `ox-stdlib-lock` — raw `Eio.Fiber`/`Switch`/`Mutex`/`Promise`/`Stream`/`Condition`/`Semaphore` outside `lib/ox`, and `Stdlib.Mutex`/`Condition`/`Semaphore` anywhere but an allow-listed C-state guard — decided by resolved path so that `open Eio` and module aliases cannot hide a call. ^nlintc-j03j
4. As a reviewer, I want `ox-discarded-result` shipped as row 87 leaves it, with its eight sites resolved, plus `ox-public-exception` (an `exception` declared in `lib/**/*.mli`) and `ox-obj-magic` (any `Obj.magic*` outside `lib/ox/once.ml`). ^nlintc-7be1
5. As a reviewer, I want `ox-race-deadline`: a deadline written as `race` or `Fiber.any` against a sleep instead of `timeout`, since `race` selects the first success and this is the mistake the core's own doctrine warns about. ^nlintc-4gjw
6. As a maintainer, I want every rule to carry its violating and clean fixture, its `docs/rules/` page, its accepted false negatives, and a line in `ox-lint --self-check`, so that row 87's triangle holds for each. ^nlintc-kdcl
7. As a maintainer, I want `scripts/caps-gate` left alone and the 17 `ox-caps-*` rules left on Semgrep in this row, with the migration decided only after `ox-lint` has run these rules over ox and all five consumers at least once. ^nlintc-ayjk

## Out of Scope

Migrating the caps rules (story 7); the interface-documentation rules (row 89); timing (row 85).
