# ox-discarded-result

Forbids discarding an expression whose inferred type is the standard two-parameter
`result` through `Stdlib.ignore` (including module aliases, opens, `@@` and `|>`)
or a wildcard/locally unused named binding (including tuple and record fields).
A used whole-value binder anywhere in an alias chain retains the containing value,
including `let (retained as _unused) = result in retained`; identity is compiler-based,
so a shadowing binder cannot exempt the earlier result. Using a tuple/record sibling
field does not retain a wildcard result, and subsequently ignoring a retained result
is still diagnosed. All-unused aliases of the same result emit one finding, not a
second finding for the inner wildcard. Local
value aliases of the standard discarders are followed by compiler binding identity.
It also rejects constant `Error` arms, including a local constant alias, recognized
unit-returning logging alone, or logging followed by a constant, and standard `Result.to_option`, `Result.iter` and
`Result.value` conversions that erase the failure. Manifest type aliases are
expanded; unrelated local functions named `ignore`
and distinct types named `result` are not violations. Canonical identities come
from the compiler's initial environment, never a locally shadowed `Stdlib`.
(^nlint-hxar, ^nlint-9ftb, ^nguide-xwuf, ^nguide-lg1m)

## Wrong

```ocaml
let save () = ignore (write ()) (* write returns (unit, error) result *)
```

## Right

```ocaml
let save () = write () (* preserve the result for the caller *)
```

Or recover from, or deliberately map, the named error. Merely matching `Error`
or logging it and returning `()` does not prove handling. Exceptions remain defects;
do not convert a typed failure to an exception just to satisfy this policy.
When best effort is intentional, make one checked local decision (^safe-pufa):

```ocaml
(* Closing is best effort; preserve the original operation's failure. *)
let _close_result = close connection
[@@ox.allow "ox-discarded-result: optional close must preserve the original failure"] in
original_result
```

A comment or underscore name alone is not a decision. The expression form is
`(ignore (close connection)) [@ox.allow "ox-discarded-result: nonempty reason"]`.
The gate accepts only one eligible rule ID and a nonempty reason, on an expression
or value binding. Unknown IDs, lists, wildcards, forbidden rules, malformed payloads
and unused enabled-rule decisions are findings, even with explicit rule selection.
Disabled-rule decisions are not called stale. Only `ox-discarded-result` and future
`ox-partial-option` / `ox-partial-list` are eligible; future IDs are rejected until
their rules are installed. There is no path-wide or capability-rule waiver.

A decision filters findings only, never parse, import, missing-artifact or stale
evidence failures (exit 2). Policy findings use exit 1; a verified clean run uses 0.
The checker validates the reason is present, not that the policy is wise.

## Finite detection horizon

This is a local policy restriction, not proof that every undiagnosed result is
handled. Unknown higher-order calls, exported bindings, polymorphic functions
instantiated only at a later call, cross-unit value aliases and opaque recovery
helpers are not resolved. Passing a result to an unknown function is not certified
handling. The check follows ordinary immutable local aliases; it does not execute
code or prove general control/data flow. Recovery calls and named-error mappings
are legitimate counterexamples to unconditional constant erasure. Explicit error
discriminants (`Error `Empty`, `Error `Timeout`) and distinct boolean/integer outcome
statuses preserve meaningful failure information. Compiler-typed boolean projections
may compute the success status (`Ok n -> n > 0 | Error _ -> false`); equal bare
constant statuses are still erasure. An expected-error assertion with unit on the
Error arm and compiler-identified `Alcotest.fail`/`failf` or terminal
`Stdlib.failwith`/`invalid_arg`/`raise`/`raise_notrace` on every opposite arm
preserves the test expectation, rather than disposing of an operational failure.
A guard comparing the actual bound error payload through a resolved standard
comparison is not recovery by itself: `Error error when error = expected -> () | _ -> ()`
still erases every outcome. The local guard exception additionally requires later
error-compatible alternatives with nonconstant, nonlogging outcomes and an unguarded
fallback. An effect only on the `Ok` branch does not qualify. A terminal expected-error
assertion or a recovery fallback qualifies; an opaque call is not certified recovery.
A bare `true` guard, an unrelated binder, or a shadowed comparison does not qualify.
The detector requires `fs_read` authority for compiler interface and environment
reads; unresolved required standard identities fail closed, not as a clean decision.
An observation match followed by
returning the same result is not disposal. Only bare constants, pure constant local
bindings/aliases, and compiler-identified standard/Logs unit log calls, alone or
followed by a constant, are proven erasure; arbitrary effectful prefixes are outside this horizon.
Ghost or unrelated-source locations cannot consume a decision, even at the same
byte offsets; source and its known default-build spelling are canonicalized. An
exact compiler source spelling is admitted only after `Artifact.check` validates
that annotation against the checker source; this is not a basename fallback.
Containment uses authored line/column coordinates: a textual preprocessor can
shift physical byte offsets while preserving those coordinates with line directives.
It still requires non-ghost scopes and findings from that exact validated source.
(^safe-1bc7, ^safe-s6km, ^safe-xls8)

## Check

Build first, then run the decider from the same Ox installation:

```sh
dune build @install
ox-lint --require-typed --rules ox-discarded-result lib/
```

In this checkout the executable is `_build/default/lib/ox_lint/main.exe`.
Findings print `file:line: ox-discarded-result: replacement` and exit 1.
Missing, stale, unreadable or partial annotations, missing dependencies, and parse
errors name the file and exit 2. Implementations need `.cmt`; interfaces need
`.cmti`. Native-only tools must retain annotation targets too; this checkout adds
byte mode plus an install-alias dependency to the two build-time executables,
so Dune retains their CMTs rather than dropping undeclared native outputs.
The imported CMI fingerprints are checked before alias expansion; missing or
changed interfaces are evidence failures, never clean findings. (^nlint-jm8g, ^nlint-2nwm)

## What the check cannot see

- A node whose inferred type is still a variable is not reported, even when later
  instantiated to `result`.
- There is no interprocedural reasoning.
- Local aliases of standard discarders are followed; opaque cross-unit aliases and
  passing a discard function as an argument remain outside the horizon.
- For preprocessed input the annotation's digest covers the generated source.
  The engine also checks the original against Dune's build copy and its timestamp;
  manually preserving timestamps while replacing a symlinked build source is not
  a supported substitute for rebuilding.

The gate declares its required source modules in
[modules.txt](<../../test/lint/modules.txt>); it never infers coverage from annotations
that happen to exist. The rule's [violating](<../../test/lint/violating/discard.ml>) and
[clean](<../../test/lint/clean/discard.ml>) fixtures are checked under `test/lint/`.
Concurrency and interface-documentation rules belong to rows 88 and 89. The
repository gate (`--repo-gate`, also accepted as `--caps-gate`) selects them and
this rule alongside all capability rules; `--rules` narrows that selection.
(^nlint-emql, ^nlint-r01u)
