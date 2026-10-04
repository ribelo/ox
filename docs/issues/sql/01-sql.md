---
status: done
package: ox_sql, ox_sql_dsl
consumer: Exergy SQLite ingestion; existing SQLite consumers
priority: P1
---

# SQLite sticky cancellation with safe transaction cleanup

## Problem Statement

The Cancellation API promises persistence when cancellation is requested before execution. The implementation only consults the flag from a SQLite progress handler every 1000 VM steps; sqlite3_interrupt while idle is ineffective. A short INSERT or COMMIT can therefore run after pre-start cancellation without ever checking the flag. Strengthening entry checks must not make ROLLBACK impossible under the same sticky token.

## Solution

Honor sticky cancellation at native statement entry and keep active interruption. Define cleanup as an explicit noncancelled ownership boundary, so failed/cancelled transactions restore a reusable connection and preserve primary plus rollback failures. Do not promise to undo a commit that already completed.

## User Stories

1. As inn's store author, I want typed table declarations, schema, predicates, projections, SELECT, INSERT, UPDATE and DELETE compilation unchanged from v1, so that its existing SQL shapes and type checks survive migration. ^nsql-4m2q
2. As inn's store author, I want SQLite open/configuration, prepared binding/reading, scripts, and diagnostic errors backed by the v1 C stubs, so that it can use WAL, foreign keys, INTEGER/TEXT/NULL and pragmas without an external database. ^nsql-7x9b
3. As inn's store author, I want an Eio-scoped, bounded connection pool with typed execution and raw query/fold/execute operations, so that concurrent store requests safely share SQLite handles and shutdown releases them. ^nsql-k3zf
4. As inn's store author, I want transaction runners that commit successful work and roll back failures, defects and interruption before a connection is reused, so that a failed ingest does not leak partial writes into later requests. ^nsql-p8na
5. As a kernel maintainer, I want direct-style migration sources and version/checksum validation with ordered application, so that database schema upgrades can be resumed and mismatches rejected. ^nsql-v5td
6. As a kernel maintainer, I want copied DSL soundness and SQLite regression tests plus offline pool/transaction/migration tests, so that the old guarantees and new lifetime boundary are exercised without network access. ^nsql-c2jw
7. As a SQLite caller, I want a cancellation request made before native entry to reject a short statement before its SQL effects, so that the documented sticky token applies even without a progress callback. ^nsql-hten
8. As a SQLite caller, I want pre-requested exec, prepare and step paths checked consistently, so that using a prepared statement cannot bypass the cancellation guarantee. ^nsql-n11a
9. As a transaction owner, I want cancellation immediately before COMMIT native entry to prevent the commit, so that a queued cancellation is not missed by a tiny commit statement. ^nsql-bgvv
10. As a SQLite caller, I want active long-running statements cooperatively interrupted and the sticky flag to remain active for subsequent protected statements, so that entry checks supplement rather than replace the progress handler. ^nsql-zckh
11. As a transaction owner, I want ROLLBACK and required cleanup to run despite a cancelled operation token, so that the connection returns to autocommit with uncommitted rows absent. ^nsql-iypi
12. As a transaction owner, I want typed body failure, raised body defect and commit failure to preserve the primary diagnosis plus any rollback failure and original defect backtrace, so that cleanup failure is not silently discarded. ^nsql-9ykc
13. As a connection owner, I want handler restoration and a fresh-token operation after cancellation to work, so that sticky cancellation is operation-scoped rather than permanent connection poisoning. ^nsql-7mzz
14. As a connection owner, I want cancellation request racing with handle close or statement cleanup to remain memory-safe and idempotent, so that the native token cannot interrupt freed state. ^nsql-tv6i
15. As a test author, I want deterministic short INSERT/COMMIT, prepared-step, long-query, cleanup and fresh-token regressions through public SQL/blocking calls, so that source-level guarantees are verified on the actual Ox binding. ^nsql-kbdp

16. As a SQL test author, I want a private post-entry VM-progress fixture distinct from the before-step gate, so that active interruption is proved deterministically without a production query-notification API. ^nsql-l98b

## Implementation Decisions

- Keep direct result-returning SQLite and generic SQL DSL execution. Domain callback error types must stay generic; Exergy errors are not forced into Sqlite.Error.t.
- The existing sticky contract is authoritative: explicitly pre-requested cancellation must be checked at relevant native entry, before SQL work or mutation. Preserve return/error classification as SQLite interruption; external Eio cancellation and defects remain distinct.
- Only cancellation known before entry is guaranteed to prevent entry. A race after execution begins is cooperative; once COMMIT has completed, later cancellation cannot make it uncommitted or justify automatic replay.
- The execution owner composes the existing pure transaction callback seam: begin, body and commit each have a separate operation-token handler scope; rollback/close run outside it, with mandatory Eio cleanup protected by that owner. Do not wrap the entire transaction in the sticky handler or nest handlers. The existing convenience transaction helper remains cancellation-neutral; no new token-aware runner is required by this ticket.
- If rollback fails or autocommit is not restored, the execution owner discards the connection instead of returning it for reuse, closes only after physical settlement, and preserves primary plus cleanup diagnostics. This ownership policy is not injected into the pure generic callback combinator.
- The generic SQL DSL transaction combinator remains pure with no Eio dependency. It already composes begin/body/commit/rollback callbacks and preserves cleanup failures; Eio cancellation shielding belongs in the SQL execution owner, not the generic builder.
- Preserve typed DSL soundness, raw SQLite escape hatches, pooling, configuration and migration policies. No checksum/version migration-policy change is required for this cancellation fix.

## Testing Decisions

- Confirmed seam: public SQLite and blocking calls with cancellation fixtures against disposable in-memory databases. Run under the supported OxCaml/Eio toolchain; Python/SQLite evidence is not an Ox regression test.
- Request before handler installation and before exec of a one-row INSERT; expect interruption and no row. Request before COMMIT in an open transaction; expect no commit, allow cleanup, then assert autocommit and no row.
- Prepare while live, request immediately before step, and prove it does not mutate; also cover pre-requested preparation and very short reads. The existing before-step native gate proves pre-entry behavior only, not active-query interruption.
- Active-query preservation needs an explicit private native test fixture: a post-entry progress-handler notification/gate, reached by a long recursive query on a blocking worker. From another fiber request the token after that notification, then release the gate and assert SQLite interruption through the real handler. The gate must not hold any lock required by token request/interrupt. Keep it test-only, outside the production public SQL API. No sleep or outside-the-VM start latch is evidence of active execution.
- Exercise the public generic transaction callback seam with begin/body/commit under separate native handler scopes and native rollback outside them. Begin and insert, request the token immediately before returning a typed body Error rather than triggering SQLite auto-rollback, then prove rollback succeeds despite the flag. Assert autocommit, no row and successful fresh-token work. This does not claim the cancellation-neutral convenience helper suppresses an enclosing token.
- Inject rollback failure/autocommit-not-restored in the execution-owner fixture: the affected connection must be discarded rather than leased again, with primary and cleanup diagnostics retained.
- Inject primary and rollback failures through the public transaction callback seam; preserve both diagnostics and raised-body backtraces. Include handler restoration on every exit and request/close races under safe ownership.
- Compose with a blocking-pool worker to prove caller cancellation never closes/reuses the handle before physical callback settlement. Existing pool/transaction/migration and compile-negative DSL tests remain unchanged; cite new IDs and ^nsql-p8na.

## Out of Scope

Interrupting a completed commit, forceful thread termination, automatic operation replay, adding Eio to the pure SQL DSL, changing Exergy schema identity/checksum policy, an ORM, or new database drivers.

## Further Notes

- Audit 2026-10-04 at Ox 08c6fc8f, unchanged relevant source at 72af4cde. Original story IDs remain. Current tests contain no Cancellation API references; prior green SQL suites did not establish this contract.
- Evidence: [sticky API:155–164](<../../../lib/sql/sqlite.mli#L155-L164>), [progress handler:196–212](<../../../lib/sql/sqlite_stubs.c#L196-L212>), [native exec/prepare:502–558](<../../../lib/sql/sqlite_stubs.c#L502-L558>), [native step:786–812](<../../../lib/sql/sqlite_stubs.c#L786-L812>), and [transaction cleanup:82–103](<../../../lib/sql_dsl/ox_sql_dsl.ml#L82-L103>).
- A file-free Python/SQLite 3.53.3 probe performed by the audit worker returned exit 0: idle interrupt, always-cancel progress handler at 1000 instructions, short INSERT and COMMIT produced one row with zero progress callbacks. This confirms the primitive behavior, not an executed Ox test.
- Exergy-owned defect, not a new Ox feature: the current ingest transaction helper can fail to roll back a raised callback/failed commit and discards rollback failure. The later migration must use the existing generic transaction contract and a shielded execution edge.
- The [blocking-pool drain repair](<../blocking/01-blocking.md>) protects ownership around native callbacks. It does not make caller cancellation synchronously stop SQLite.
- Additional verified P2 concern, not an Exergy raw-SQL prerequisite: [Pool timeout application:89–95](<../../../lib/sql/pool.ml#L89-L95>) silently ignores a requested timeout when no clock is supplied; [public timeout-bearing operations](<../../../lib/sql/pool.mli#L9-L33>) also run native statements synchronously on the Eio thread. [Current timeout test:87–98](<../../../test/sql/run.ml#L87-L98>) proves checkout timeout only. Before strengthening pooled-operation deadlines, ratify checkout-only versus full-native-work semantics, reject or structurally prevent a timeout without clock authority, and prove heartbeat responsiveness plus lease retention until physical settlement/rollback. This P2 follow-up is not included in the ready cancellation implementation slice. Do not silently adopt Pool for Exergy or ticket an async blueprint driver.

Verified 2026-10-04: [SQLite cancellation tests](<../../../test/sql/test_sqlite_cancellation.ml>) `native_entry`, `commit_entry`, `body_failure_rollback`, `commit_failure_rollback`, `primary_and_rollback_failures`, `raised_body_rollback`, `restoration`, `active_interrupt`, `request_close_cleanup`, and `blocking_caller_cancellation` passed; the full SQL suite passed 34 tests.
`@install`, `dune test`, and `@fmt` passed; caps-gate was verified by the lead on an isolated tree. Rollback-failure connection discard is Exergy-owned; test fixtures demonstrate caller-selected disposal only.
