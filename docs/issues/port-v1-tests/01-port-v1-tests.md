---
status: completed
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

## Port status (complete)

The historical inventory counts Alcotest registrations in each `v1:test/core_common/*_common_suites.ml` (and named scenarios in the shared interruptibility helper). A single eta-next test function can contain several independently labelled historical scenarios. Counts distinguish historical cases from new Alcotest registrations; every retained registration has its own named scenario/assertion, even when several share a test function. The 213 registered cases are 104 ported and 109 dropped, with none pending. The additional 19 shared interruptibility helpers are classified separately.

| Historical suite | v1 cases | Ported | Dropped | Pending | Drop reason or remaining work |
| --- | ---: | ---: | ---: | ---: | --- |
| `cause_exit` | 11 | 2 | 9 | 0 | No captured finalizer strings, diagnostic equality, materialized die identity or `finalizer_of_cause` in the smaller Cause/Exit API (9). Classification and combinator behavior are covered by the labelled core tests. |
| `cause_render` | 13 | 13 | 0 | 0 | All corpus cases, newline freedom and multiline pretty output asserted by name; the compact grammar reflects eta-next's Cause constructors. |
| `effect_resource_timeout` | 41 | 32 | 9 | 0 | No daemon runtime (3), `timeout_as` (5), or `with_resource let@` syntax (1); direct-style `Scope`/`Resource` covers surviving bracket, acquisition, finalizer, timeout and parallel rollback cases. |
| `effect_retry_repeat` | 41 | 23 | 18 | 0 | No `retry_or_else` API (9), unbounded `forever` execution API (4), or interpreter-specific composite Cause recovery (5); 23 bounded schedule, retry, repeat, jitter, defect and resource-lifetime cases ported. |
| `supervisor` | 42 | 17 | 25 | 0 | No managed child / supervised-background handles (10: 1–9, 25), `on_exit` observer / typed cleanup API (5: 14–17, 21), threshold / multi-failure supervisor API (2: 32–33), or request-cancel / runtime command API (8: 35–42). Cases 10–13, 18–20, 22–24, 26–31 and 34 ported. |
| `resource` | 25 | 5 | 20 | 0 | No refreshable manual/automatic resource cache (20); four sleep / mock-clock cases and LIFO finalizers ported. Mock clock auto-advance substitutes explicit `set_time`. |
| `stress` | 14 | 8 | 6 | 0 | No pool (1), semaphore (1), channel (1), `all_settled` (1), interpreter-based randomized `Effect.t` composition (1), or `map_par` (1). The eight retained resource / race / all cases run at bounded sizes instead of v1 load. |
| `logger` | 7 | 4 | 3 | 0 | No logfmt label encoder, stdout/stderr console routing, or v1 writer critical-section implementation (3). JSON escaping, levels/fields, minimum severity and writer recovery are covered. |
| `effect_interruptible_shared` | 19 named helper cases | 0 | 19 | 0 | No interpreter, SPI runtime contract or `Effect.interruptible` mask; Eio cancellation is tested separately via scope release and retry interruptions. |

**Kernel findings:** `Concurrent.race` tried to cancel already-finished contexts after a later branch succeeded; skip finished contexts according to `Eio.Cancel.get_error`. `Cause.pp_compact` let a typed printer place raw newlines in its promised one-line output; escape carriage returns and newlines. `Concurrent.with_background` swallowed loser cleanup defects once body had published a typed failure; propagate the cleanup exception from the child switch. Because its result type is `('a, 'e) result`, that defect can override, but cannot contain, the typed body error as a `Cause.Suppressed` without changing the public API. `Concurrent.all` also lost a nested parallel loser's finalizer defect when its caller was canceled while waiting: the canceled promise wait hid a worker exception. Wait for the child switch to settle under cancellation protection, remember worker defects, and re-raise a defect rather than the canceled await; the nested `with_background` / `par` regression confirms the contract that parallel defects raise, never become `Error` values.

**Direct-style adaptations:** Scope finalization replaces v1 materialized finalizer state and `on_exit` observers; `Eio_mock` auto-advances rather than exposing explicit `set_time`; randomized retry jitter is checked against bounds rather than a seedable runtime PRNG; bounded stress loops use seeded interleaving variation instead of v1 load. The retained supervisor body-first case ports the plain background branch only: its named, observability-named and traced variants have no eta-next counterparts. No v1 interpreter, managed child, or runtime command API is recreated.

**Verification:** `nix develop -c env DUNE_BUILD_DIR=_build_v1port dune build @install` and `nix develop -c env DUNE_BUILD_DIR=_build_v1port dune test` passed (90 core tests; observability suite passed).  
`nix develop -c env DUNE_BUILD_DIR=_build_v1port dune build @fmt` passed; 104 of 213 historical registrations ported, 109 dropped for the suite-specific reasons above, zero pending (plus 19 separately classified shared helpers).

