# ox-stdlib-lock

Story: ^nlintc-j03j; evidence: ^nlintc-kdcl.

Refuses values originating in Stdlib/system-thread `Mutex`, `Condition` and
`Semaphore`, including nested semaphore modules. A domain-blocking lock is not
an Eio fiber lock. Use fiber-aware `Eio.Mutex`, `Eio.Condition` or `Eio.Semaphore`;
`Ox.Mutex` becomes the replacement when row 65 lands. Never hold a domain-blocking
lock across a fiber suspension. References as well as direct calls are checked.

**Exact project-root-relative allowances, each with a reason:**

- [sqlite.ml](<../../lib/sql/sqlite.ml>): guards SQLite C calls contended by system threads.
- [listener.ml](<../../lib/ipc/listener.ml>): guards a Hashtbl synchronously, without yielding.

These guards are correct today and are not migrated. The rule stops the next
unauthorised use. There is no prefix/directory allowance.

**Accepted false negatives.** Typed module/value origin resolution follows opens
and module aliases, not value aliases or user wrappers. Custom blocking locks and
C implementations are outside the set. Lock duration is not analysed; the two
allowances rest on the reviewed call sites, not a inferred no-yield guarantee.

## Evidence

[Violating fixture](<../../test/lint/violating/stdlib_lock.ml>) and
[clean fixture](<../../test/lint/clean/stdlib_lock.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.
