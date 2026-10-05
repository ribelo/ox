# ox-assertion-effects

Stories: ^safe-pcom, ^safe-u7cx, ^safe-28t6; shared evidence: ^safe-y047, ^safe-czoe.

## Failure and replacement

An assertion condition is omitted by `-noassert`. Required mutation or I/O in it
therefore vanishes from a release consumer. Even one effectful predicate call is
unsafe; a semicolon alone is not evidence of an effect.

Perform required work **outside** the assertion. Ordinary validation must also
remain ordinary code, returning an error (or failing the test explicitly), not
become a removable assertion:

```ocaml
let check cell =
  Stdlib.incr cell;
  if !cell = 1 then Ok () else Error `Unexpected_value
```

A legitimate counterexample is `assert ((); true)`: an effect-free sequence.
Creating an uncalled function or lazy value, or an unsaturated application of a
known multi-argument function, does not execute its body. Supplied arguments are
still evaluated; calling an outer stage that produces another closure also runs
that stage. An immediately called closure executes its body. Assertion failure itself is not a
write/I/O finding.

## Finite typed horizon

The visitor consumes checked compiler evidence, after `Artifact.setup`. It compares
normalized compiler value identities; opens and real module aliases work, and
same-spelled lexical/module shadows are not mistaken for standard functions.
Local bindings use compiler identifier stamps, not names.

Proved findings cover direct record/instance-variable/local-variable assignment and fully applied
resolved `Stdlib.incr`, `decr`, `:=`, `Array.set`, `Bytes.set`,
`Buffer.add_string`, `Hashtbl.replace`, `print_endline`, `output_string`, and
`Atomic.set`, `Atomic.exchange`, `Atomic.fetch_and_add`.
It follows first-order lexical function definitions, value aliases, captured
partial applications, immediate closures and function cases. Recursion remains
named unverified. A helper finding points at the removable assertion invocation.
Branches/guards are considered potentially evaluated; this is not reachability
or termination analysis.

Pinned standard primitives `ignore`, `not`, `ref`, `!`, integer arithmetic,
physical equality and Boolean operators have no write/I/O callback. Standard
polymorphic comparison is accepted only for an inferred primitive scalar operand
(int, bool, char, string, unit or float), or when both operands have the exact
built-in list type and one is its literal empty constructor. Empty versus empty
or cons compares tags without visiting elements, so even a list of functions
can safely be compared with `[]`. The constructor is established by compiler
type identity and its nullary constant representation, not spelling. Operand
expressions are still evaluated and checked: `(incr cell; callbacks) = []`
violates, and `unknown_callback () = []` remains named unverified for that call.
Nonempty functional-list comparisons, custom-type comparisons and a different
type reusing `[]` constructor spelling remain unverified. This does not
generalize structural-comparison purity.

Exact `Stdlib.Atomic.get` is also a no-write/no-I/O load: pinned
5.4.0+ox declares `%atomic_load`, whereas `set`, `exchange` and `fetch_and_add`
declare updating primitives. This does not promise referential transparency or
that all synchronization APIs are safe. Calling a function returned by an ordinary
or atomic reference read is still unverified.

Opaque parameters, separately compiled helpers, object dispatch/initialization,
optional/lazy helper parameters, lazy pattern forcing, binding operators, probes,
ownership overwrite, staged expressions, returned helper functions and other calls
are **named undecided**, not proved effects and not a policy violation. This
includes native functions advertised as pure/read-only outside the exact pinned
horizon (for example `Array.get`). Strict typed scans and the repository gate must
fail on that uncertainty. No waiver or allow-list; move the call/ordinary
validation outside the assertion or supply a separately justified semantic rule.
Suspension alone does not prove mutation or I/O, so concurrency analysis is not
reused as effect evidence. This is a bounded typed walk of assertion conditions,
not a general effect interpreter or a claim of program-wide purity.

## Evidence and integration

[Violating fixture](<../../test/lint/violating/assertion_effects.ml>) and
[clean replacement](<../../test/lint/clean/assertion_effects.ml>) have interfaces.
[Typed consumer tests](<../../test/lint/safety_assertion_effects/check_typed.ml>)
compile copied evidence from its own nested Dune project; the private engine
harness remains outside that boundary. Negative/unknown programs are deliberate
evidence, not ordinary gate corpus. Canonical fixtures are compiled from copies
in the same isolated temporary consumer, never registered as ordinary negatives.

[Runtime checks](<../../test/lint/safety_assertion_effects/runtime-check.sh>) compile
and execute actual normal/`-noassert` consumers: the broken write changes from 1
to 0, the repaired write stays 1, and repaired ordinary validation still fails
with exit 7 in both builds.

[Installed checks](<../../test/lint/safety_assertion_effects/installed-check.sh>)
require explicit `BIN`, `SHARE` and compiler-matched `STDLIB` paths. Both
compilation and invocation occur outside checkouts; fixtures and `--self-check`
use the installed root. The script checks selected-rule and strict repository
outcomes for clean (0), proved-effect (1), named-unknown (2), stale annotation (2)
and missing annotation (2) consumers. The latter two retain real Dune source
membership; explicit scans must not silently repair their evidence. Consumer and
invocation directories are created under `/var/tmp`, outside checkout ancestry.
Numeric statuses and separate stdout/stderr logs remain in `LOG_DIR` (or a fresh
`/var/tmp` logs directory when omitted). A source build is not installation
evidence.
