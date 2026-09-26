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
