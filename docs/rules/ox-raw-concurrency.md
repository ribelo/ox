# ox-raw-concurrency

Story: ^nlintc-j03j; evidence: ^nlintc-kdcl; deliberate dormancy: ^nlintcov-r3k8.

The typed decider identifies `Eio.Fiber.fork*`, `both/pair/all/any/first`,
`Eio.Fiber.List.*`, `Eio.Switch.run`, `Switch.on_release*` and `Eio.Mutex.*`
by normalized origin. Its diagnostic names `Scope.fork @ once`, `Spawner.t`
and `Ox.Mutex` as the future replacements.

**Application policy: no path.** Row 88 ships and tests the decider, but neither
default selection nor explicit `--rules ox-raw-concurrency` applies it to any
source. Row 66's “outside lib/ox” boundary is wrong: ox_http, ox_ipc, ox_rpc and
ox_process legitimately form the layer over Eio. Rows 61, 64 and 65 have not yet
landed the replacements (once-taking Scope.fork, Spawner.t, Ox.Mutex). Activation requires all three replacements to exist as public, usable APIs,
their ownership guarantees to be tested, and every existing raw site in Ox and
its consumers to have been migrated or assigned an honest structural boundary.
That delivery changes the applicability predicate and the deliberately-inactive
CLI regression together. Until then the rule is a tested decider, not an active
enforcement claim; file exemptions are not an activation strategy.
There are no allow-list entries: the rule is dormant, not broadly allow-listed.
Fixtures call the decider directly so its behavior is tested without enabling it.

**Accepted false negatives.** Value aliases, user wrappers and functor-dependent
paths are not followed. Other concurrency APIs are outside the listed set.
While dormant, **every production use is intentionally unreported**; this is
not a claim that current raw Eio calls violate an available Ox API.

## Evidence

[Violating fixture](<../../test/lint/violating/raw_concurrency.ml>) and
[clean fixture](<../../test/lint/clean/raw_concurrency.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.

Compiled negative fixtures belong to a nested Dune project, excluded structurally from the default workspace scan. Explicit source and annotation scans still inspect their evidence. The [deployment regression](<../../test/lint/deployment/check.sh>) verifies that both default and explicit rule selection deliberately report no raw-concurrency finding on a fresh, compiled violating source outside any fixture workspace. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).
