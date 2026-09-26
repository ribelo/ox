---
status: ready-for-agent
package: test/core, test/observability
consumer: every consumer; the laws these tests encode are what makes the combinators trustworthy
---

# Port v1's behavioural tests for the retained semantics

## Problem Statement

v1 accumulated large behavioural suites for exactly the semantics eta-next keeps — cause classification and rendering, timeout and resource release, retry and repeat, the race/par/background laws, cancellation, stress — and they caught many real bugs. eta-next's 178 tests were written from the specs; they do not yet carry that history.

## Solution

Port the v1 suites whose subject survives, case by case, onto eta-next's direct-style API; drop the cases whose subject is gone (the interpreter, runtime contract, pools, queues, promise, portable queue, string helpers) with a one-line reason each.

## User Stories

1. As a kernel maintainer, I want `v1:test/core_common/cause_exit_common_suites.ml` and `cause_render_common_suites.ml` ported, so that Cause/Exit classification and rendering keep their v1 laws. ^nport-v4oy
2. As a kernel maintainer, I want `effect_resource_timeout_common_suites.ml` ported onto `Timeout` and `Resource`, so that timeout-with-release semantics are covered as in v1. ^nport-bo4a
3. As a kernel maintainer, I want `effect_retry_repeat_common_suites.ml` ported onto `Retry` with the mock clock, so that schedule-driven behaviour keeps its v1 cases. ^nport-rry6
4. As a kernel maintainer, I want the `supervisor_common_suites.ml` cases about background, par, race, finalizer visibility, external cancellation classification and "nested fibers physically exited" ported onto `Concurrent` and `Scope`, so that the laws that took v1 months to get right are kept. ^nport-ivyn
5. As a kernel maintainer, I want `resource_common_suites.ml` and the applicable `effect_interruptible_shared.ml` cases ported, so that release-under-cancellation is covered. ^nport-kaym
6. As a kernel maintainer, I want `stress_common_suites.ml` ported with its sizes reduced to keep the suite under ten seconds, so that concurrency bugs that only appear under load are still hunted. ^nport-ozuw
7. As a kernel maintainer, I want the `logger_common_suites.ml` cases about levels, fields and rendering ported onto `eta_observability`, so that the journal contract inherits v1's cases. ^nport-lve1
8. As a kernel maintainer, I want a table in the spec's status listing each v1 suite with ported / dropped counts and the reasons for drops, so that the port is auditable. ^nport-ubcd

## Implementation Decisions

- `git show v1:test/core_common/<file>` is the source; port meaning, not text: a v1 case built on `Effect.t` becomes the same scenario over thunks and `Scope.run`.
- Where a v1 case encodes interpreter-specific behaviour (fusion, blueprint construction, SPI), drop it with the reason "no interpreter".
- Ported tests cite the eta-next story they now protect where one exists, else the v1 suite name.
- Any v1 case that fails on eta-next is a finding: fix the kernel or record why the new behaviour is intended, in the spec's status, before marking done.

## Testing Decisions

- The port is the test. Suite time budget: whole `dune test` under two minutes on this machine.

## Out of Scope

HTTP, AI, SQL, stream, signal, crux suites: ported with their packages when a consumer pulls them.

## Port status (in progress)

The historical inventory counts Alcotest registrations in each `v1:test/core_common/*_common_suites.ml` (and named scenarios in the shared interruptibility helper). A single eta-next test function can contain several independently labelled historical scenarios. Counts below distinguish historical cases from the number of new Alcotest registrations; cases still being audited are **not** counted as dropped. Do not mark this spec complete while any pending cases remain.

| Historical suite | v1 cases | Ported | Dropped | Pending | Drop reason or remaining work |
| --- | ---: | ---: | ---: | ---: | --- |
| `cause_exit` | 11 | 2 | 9 | 0 | No captured finalizer strings, diagnostic equality, materialized die identity or `finalizer_of_cause` in the smaller Cause/Exit API (9). Classification and combinator behavior are covered by the labelled core tests. |
| `cause_render` | 13 | 13 | 0 | 0 | All corpus cases, newline freedom and multiline pretty output asserted by name; the compact grammar reflects eta-next's Cause constructors. |
| `effect_resource_timeout` | 41 | 14 | 9 | 18 | No daemon runtime (3), `timeout_as` (5), or `with_resource let@` syntax (1). Pending: parallel acquisition rollback, bracket subcases and ownership/finalizer variants. |
| `effect_retry_repeat` | 41 | 17 | 15 | 9 | No `retry_or_else` (9), `forever` (4), or composite Cause recovery through Retry (2); remaining schedule, defect and resource-lifetime cases need explicit assertions. |
| `supervisor` | 42 | 9 | 15 | 18 | No managed child handle/cancel request API (6), supervised-background handle (3), runtime cancel/fail_scope (2), or named/traced background variants (4). Remaining background/par/race winner and cleanup interleavings need individual scenarios. |
| `resource` | 25 | 1 | 20 | 4 | No refreshable manual/automatic resource cache (20); virtual sleep cases remain pending. LIFO finalizers are ported. |
| `stress` | 14 | 3 | 5 | 6 | No pool, semaphore, channel, all_settled or map_par APIs (5); remaining reduced-size combinations need explicit checks. |
| `logger` | 7 | 4 | 3 | 0 | No logfmt label encoder, stdout/stderr console routing, or v1 writer critical-section implementation (3). JSON escaping, levels/fields, minimum severity and writer recovery are covered. |
| `effect_interruptible_shared` | 19 named helper cases | 0 | 19 | 0 | No interpreter, SPI runtime contract or `Effect.interruptible` mask; Eio cancellation is tested separately via scope release and retry interruptions. |

**Kernel findings:** `Concurrent.race` tried to cancel already-finished contexts after a later branch succeeded; skip finished contexts according to `Eio.Cancel.get_error`. `Cause.pp_compact` let a typed printer place raw newlines in its promised one-line output; escape carriage returns and newlines. `Concurrent.with_background` swallowed loser cleanup defects once body had published a typed failure; propagate the cleanup exception from the child switch. Because its result type is `('a, 'e) result`, that defect can override, but cannot contain, the typed body error as a `Cause.Suppressed` without changing the public API.

