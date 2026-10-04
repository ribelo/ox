# ox-public-exception

Story: ^nlintc-7be1; evidence: ^nlintc-kdcl.

The Parsetree tier refuses public `exception` declarations, including nested
signatures and exception rebindings, in interfaces. Hide implementation exceptions
and expose `('a, 'error) result` edges; do not remove a public exception without
a consumer migration.

**Exact project-root-relative allowances:**

- [ox_sql.mli](<../../lib/sql/ox_sql.mli>): existing public SQL exception API is used by inn; migration requires a consumer-coordinated row.
- [types.mli](<../../lib/sql/types.mli>): existing SQL Types exception API must remain compatible with inn.
- [ox_sql_dsl.mli](<../../lib/sql_dsl/ox_sql_dsl.mli>): existing SQL DSL exception API must remain compatible with inn.
- [tls_flow.mli](<../../lib/http/tls_flow.mli>): existing TLS exception API must remain compatible with consumers.
- [sqlite.mli](<../../lib/sql/sqlite.mli>): existing SQLite exception API requires an inn-compatible consumer migration.
- [ox_sql_dsl_query.mli](<../../lib/sql_dsl/ox_sql_dsl_query.mli>): existing SQL query exception API requires an inn-compatible consumer migration.

The policy applies only to `.mli`: an exception inside a module type written in
a `.ml` is not a published interface and is not reported.

**Follow-up row.** Inventory consumers' catches/raises (especially inn), design
result-returning SQL/DSL/TLS boundaries and error variants, migrate callers and
implementation edges together, then remove the exceptions and these allowances.
Row 88 changes no public API and touches no consumer repository.

**Accepted false negatives.** Exception exposure through `include` or an alias
to a separately declared module type is not expanded by this syntax-only rule.
Implementation exports without an explicit interface are not inferred. No
cross-unit API analysis; allow-listed interfaces intentionally remain unchecked.

## Evidence

[Violating fixture](<../../test/lint/violating/public_exception.mli>) and
[clean fixture](<../../test/lint/clean/public_exception.mli>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.
