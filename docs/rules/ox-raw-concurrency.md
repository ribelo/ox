# ox-raw-concurrency

Story: ^nlintc-j03j; evidence: ^nlintc-kdcl.

The typed decider identifies `Eio.Fiber.fork*`, `both/pair/all/any/first`,
`Eio.Fiber.List.*`, `Eio.Switch.run`, `Switch.on_release*` and `Eio.Mutex.*`
by normalized origin. Its diagnostic names `Scope.fork @ once`, `Spawner.t`
and `Ox.Mutex` as the future replacements.

**Application policy: no path.** Row 88 ships and tests the decider, but neither
default selection nor explicit `--rules ox-raw-concurrency` applies it to any
source. Row 66's “outside lib/ox” boundary is wrong: ox_http, ox_ipc, ox_rpc and
ox_process legitimately form the layer over Eio. Rows 61, 64 and 65 have not yet
landed the replacements (once-taking Scope.fork, Spawner.t, Ox.Mutex). The row
that delivers those replacements enables the whole rule; file exemptions are not
an activation strategy.
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
