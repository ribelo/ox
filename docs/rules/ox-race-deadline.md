# ox-race-deadline

Story: ^nlintc-4gjw; evidence: ^nlintc-kdcl; clock-specific APIs and corrected
selection policy: ^nmono-8jcy ^nmono-m4tg.

A visible sleeping branch of `Ox.Concurrent.race`, `Ox.Concurrent.race_first`
or `Eio.Fiber.any` is treated as a deadline written as a race. Use
[`Ox.Timeout.timeout`](<../../lib/ox/timeout.mli>) with a wall clock or
[`Ox.Timeout.timeout_mono`](<../../lib/ox/timeout.mli>) with a monotonic clock.
Do not change clock kind to satisfy the rule: an elapsed-time deadline on a
monotonic clock must remain independent of wall-clock corrections.

## Selection policy

- `Concurrent.race` selects the first **success** among typed results. A sleeping
  branch returning ``Error `Timeout`` does not stop still-running work: the race
  continues until a success or until every branch has failed. A sleeping branch
  returning `Ok` instead manufactures a success, not a typed deadline failure.
  Exceptions still end the race; “first success” does not mean ignoring defects.
- `Concurrent.race_first` and `Eio.Fiber.any` select the first **settlement**,
  success or failure. A sleeping branch returning ``Error `Timeout`` can end
  these races; it is not ignored as it is by first-success `race`. They are still
  the wrong abstraction for expressing a wait's deadline.
- Both timeout APIs return the callback's result if it settles before the
  deadline, or cancel and await it on expiry and return ``Error `Timeout``.
  They use Eio's cancellation machinery and preserve external interruption and
  cleanup-defect semantics. They do not create or close the caller's switch:
  cleanup of a switch opened inside the callback is awaited, while resources
  registered on an enclosing switch remain owned by that switch.

For a `Duration.t` and a callback returning a result whose error row includes
`` `Timeout ``, the replacements keep the same call shape:

```ocaml
Ox.Timeout.timeout ~clock:wall_clock duration take_input
Ox.Timeout.timeout_mono ~clock:mono_clock duration take_input
```

**Diagnostic:** “use Ox.Timeout.timeout (wall clock) or Ox.Timeout.timeout_mono
(monotonic clock) for deadlines; race selects first success, race_first/Fiber.any
select first settlement (success or failure)”.

## Detection and limits

The typed tier resolves combinator and sleep origins through opens/module aliases.
Known sleeps are Eio Time sleep/sleep_until, Mono equivalents (including sleep_span
when available), Time.Timeout.sleep, Eio_unix.sleep and Ox.Concurrent.sleep where
those paths exist. Races without a visible sleeping branch remain clean.
No allow-list entries.

**Accepted false negatives.** Sleep behind a wrapper, value alias, opaque branch
list, or callback argument is not followed. Arbitrary clocks/timers and custom
race combinators are outside the finite set. A visible sleep used as real work
in a race is conservatively treated as a deadline; the rule does not prove the
branch's semantic intent or inspect durations.

## Evidence

[Violating fixture](<../../test/lint/violating/race_deadline.ml>) and
[clean fixture](<../../test/lint/clean/race_deadline.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.

[Monotonic timeout regressions](<../../test/core/timeout_tests.ml>) cover
result/defect propagation, deadline and external cancellation, nested deadlines,
callback cleanup, enclosing-switch ownership, and forward/backward wall-clock
jumps without changing the monotonic deadline (^nmono-r2pk).

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
