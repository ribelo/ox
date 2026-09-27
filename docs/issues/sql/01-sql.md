---
status: completed
package: eta_sql, eta_sql_dsl (SQLite C binding; stdlib, Eio, eta, SQLite C library, alcotest tests)
consumer: inn (lib/store.ml; test/test_inn.ml)
---

# SQLite and typed SQL for inn

## Problem Statement

inn stores spans, logs, metrics and trace summaries in SQLite. It declares typed tables and builds schemas and CRUD/search statements with Eta_sql, runs them through a pooled connection, and uses raw SQL for SQLite pragmas. eta-next has no SQL package; v1's effect-bound connection and pool cannot run directly on Eio.

## Solution

Copy the pure v1 SQL DSL and SQLite C connector with their applicable tests. Rewrite connection, pool and migration execution as direct-style result-returning operations over Eio, with scoped pool lifetime, bounded leases, typed errors and transaction rollback. Preserve the typed builders and intentional raw escape hatch used by inn.

## User Stories

1. As inn's store author, I want typed table declarations, schema, predicates, projections, SELECT, INSERT, UPDATE and DELETE compilation unchanged from v1, so that its existing SQL shapes and type checks survive migration. ^nsql-4m2q
2. As inn's store author, I want SQLite open/configuration, prepared binding/reading, scripts, and diagnostic errors backed by the v1 C stubs, so that it can use WAL, foreign keys, INTEGER/TEXT/NULL and pragmas without an external database. ^nsql-7x9b
3. As inn's store author, I want an Eio-scoped, bounded connection pool with typed execution and raw query/fold/execute operations, so that concurrent store requests safely share SQLite handles and shutdown releases them. ^nsql-k3zf
4. As inn's store author, I want transaction runners that commit successful work and roll back failures, defects and interruption before a connection is reused, so that a failed ingest does not leak partial writes into later requests. ^nsql-p8na
5. As a kernel maintainer, I want direct-style migration sources and version/checksum validation with ordered application, so that database schema upgrades can be resumed and mismatches rejected. ^nsql-v5td
6. As a kernel maintainer, I want copied DSL soundness and SQLite regression tests plus offline pool/transaction/migration tests, so that the old guarantees and new lifetime boundary are exercised without network access. ^nsql-c2jw

## Implementation Decisions

- Copy `git show v1:lib/sql_dsl/*` and `git show v1:lib/sql/{sqlite,sqlite_stubs,types,value,row,dsl,eta_sql}*`, adapting only wiring and error interfaces necessary for direct style. DSL schema is unrelated to removed eta_schema (ADR-0008).
- Rewrite v1 `lib/sql/{connection,pool,migrate}.{ml,mli}`; no Effect.t, Eta runtime, or Eta_blocking dependency. Pool leases and cancellation must settle before reuse. Eio switch owns final shutdown.
- ppx_sql is deferred: v1 requires ppxlib, unavailable on OxCaml 5.4; inn has no PPX uses and declares all tables manually. Lead selected deferral; a future consumer can request a compiler-libs preprocessor.

## Testing Decisions

- Port DSL type/soundness tests and binding tests where applicable. Add integration tests under test/sql with in-memory SQLite, bounded pool checkout and timeout, raw pragma, typed CRUD, transaction rollback and migrations; test names cite the stories.

## Out of Scope

ppx_sql and its tests (no inn usage; requires ppxlib), other database drivers, ORM, network database access, inn source changes.

Verification: `dune build eta_sql.install eta_sql_dsl.install` and `dune test test/sql` passed (24 story-linked runtime tests and 21 copied type-negative fixtures). Scoped `@lib/sql/fmt`, `@lib/sql_dsl/fmt`, and `@test/sql/fmt` passed; OxCaml-mode files are listed in `.ocamlformat-ignore` under the existing formatter policy. Full-tree gates belong to integration while sibling rows are in progress.
