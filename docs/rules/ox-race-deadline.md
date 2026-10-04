# ox-race-deadline

Story: ^nlintc-4gjw; evidence: ^nlintc-kdcl.

A branch of `Ox.Concurrent.race`, `race_first` or `Eio.Fiber.any` that calls
known sleep is a deadline written as a race. Use `Ox.Timeout.timeout` instead.
`Concurrent.race` chooses the first **success**, so a sleeping branch that returns
`Error Timeout` does not stop the work: it can continue until success. This is a
correctness bug, not a style preference. `race_first` and `Fiber.any` end on the
first completion, but timeout still states and owns the deadline explicitly.
Races without a visible sleeping branch remain clean.

The typed tier resolves combinator and sleep origins through opens/module aliases.
Known sleeps are Eio Time sleep/sleep_until, Mono equivalents (including sleep_span
when available), Time.Timeout.sleep, Eio_unix.sleep and Ox.Concurrent.sleep where
those paths exist. No allow-list entries.

**Accepted false negatives.** Sleep behind a wrapper, value alias, opaque branch
list, or callback argument is not followed. Arbitrary clocks/timers and custom
race combinators are outside the finite set. A visible sleep used as real work
in a race is conservatively treated as a deadline; the rule does not prove the
branch's semantic intent or inspect wall-clock durations.

## Evidence

[Violating fixture](<../../test/lint/violating/race_deadline.ml>) and
[clean fixture](<../../test/lint/clean/race_deadline.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
