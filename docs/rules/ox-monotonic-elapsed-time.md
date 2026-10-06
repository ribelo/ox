# ox-monotonic-elapsed-time

Wall time describes civil dates and protocol timestamps, not elapsed budgets.

The typed rule checks numeric subtraction/comparison of two wall-origin values,
and wall-origin delay arguments to `Eio.Time.sleep`, `Eio.Time.with_timeout` and
`Eio.Time.Mono.sleep`. Use `Eio.Time.Mono.now` with `Mtime.span` for elapsed time.

Sources are compiler-resolved `Eio.Time.now`, `Unix.gettimeofday`, and
`Ox_caps.Cap_unix.gettimeofday`. Local aliases and ordinary arithmetic or
numeric conversions preserve wall origin. Same-spelled local modules do not.

Scalar-minus-wall is a civil delay and stays clean. Logging, formatting, metadata
and opaque calls are not elapsed sinks. A wall value passed through an opaque
transformation is named undecided only at a checked subtraction/comparison or
sleep/timeout use. Duration and Schedule are not independent sink roots.

The rule does not instantiate generic local helpers, infer callback effects, or
build interprocedural summaries. Generic scalars and unrelated recursion stay
clean; unsupported values with no known wall source are outside this rule.

The default gate leaves this candidate dormant; explicit `--rules
ox-monotonic-elapsed-time` runs the audit, not consumer activation.

Native controls compile interfaces first against real Eio/Mtime/Unix/Ox_caps,
assert exact physical diagnostic sites, and check a relocated installed CLI.
