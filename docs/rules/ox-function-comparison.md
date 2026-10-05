# ox-function-comparison

Reject unsupported structural comparison of functions at directly known arrow types
(^safe-eeso, ^safe-doj9, ^safe-2led). This is a correctness finding, not a preference for
one equality spelling. OCaml accepts these type instantiations, but structural
comparison is not defined for closures and can raise `Invalid_argument` at runtime.
The diagnostic does **not** promise that every identity fast path necessarily raises.

## Detection horizon

The compiler-matched typed decider resolves the actual Stdlib values `=`, `<>`,
`<`, `>`, `<=`, `>=` and `compare` through Paths. It reports the completed
application when either operand's head-expanded type is an arrow. This includes
transparent function-type abbreviations, Stdlib module aliases and opens.

Finite local flow follows simple immutable value aliases in the current annotation,
alias chains, direct partial applications completed later, and simple let/open callee
expressions. Identifier stamps distinguish shadowing; cycles stop resolution. An
unapplied comparator or a one-argument partial application alone is not a comparison.

| Evidence | Decision |
| --- | --- |
| Resolved Stdlib comparison, fully applied, directly known arrow operand | Violation |
| Physical `==` / `!=`, dedicated or user-defined comparators | Accepted |
| Ordinary data equality/ordering, including aliases | Accepted |
| Closure-containing lists, records, tuples, arrays and other containers | Outside first horizon; no recursive comparability proof |
| Unresolved polymorphic or abstract operand type | Outside first horizon |
| Higher-order wrappers/parameters, tuple destructuring, heap flow, exported value aliases in other modules/units | Outside finite alias horizon |
| Missing/stale/incomplete annotations or missing compiler imports | Evidence failure, never a clean decision |

A clean run means no supported direct function comparison was found. It does not
certify a polymorphic helper or closure-containing container as comparable. Function
comparison has no policy-exception waiver; no unknown evidence is suppressed.

## Replacement and legitimate counterexamples

Avoid the comparison, or compare a stable domain identifier with an appropriate
comparator. For example, give an action an `id : int` and compare `Int.equal a.id b.id`,
not its `run : int -> int` field. This preserves domain identity when the implementation
closure changes. Physical equality is legitimate when **identity** is actually the
contract; it is not extensional equality. A dedicated comparator can implement a
specific domain contract. No rule advice invents equality of arbitrary functions.

## Evidence and activation

The [violating fixture](<../../test/lint/violating/function_comparison.ml>) covers all
seven operators, aliases, opens and completed partial applications. The
[clean fixture](<../../test/lint/clean/function_comparison.ml>) covers physical identity,
user/shadowed comparators, ordinary data, polymorphism, containers and domain IDs.
[Standalone tests](<../../test/lint/safety_function_comparison/test_function_comparison.ml>)
use checked Artifact evidence and assert exact application lines and columns. The
[runtime control](<../../test/lint/safety_function_comparison/evidence/runtime.ml>)
demonstrates an actual Invalid_argument and the domain-ID replacement on the pinned
OxCaml compiler. Negative compiled evidence stays in its own nested Dune project.

The [installed-CLI script](<../../test/lint/safety_function_comparison/installed_cli.sh>)
asserts the exact rule ID, sites and diagnostic count, clean controls, installed assets
and nonzero missing/stale evidence. It requires explicit installed binary and share
paths outside any checkout; self-check is forced to those resources and all consumer
compilation and CLI invocation run in a validated independent temporary directory.
It never copies checkout fixtures or borrows source-tree assets. Run after shared
registration and asset installation by the lead:

```sh
nix develop -c bash test/lint/safety_function_comparison/installed_cli.sh /PREFIX/bin/ox-lint /PREFIX/share/ox_lint
```

The decider alone is not active enforcement.

The [typed corpus audit](<../../test/lint/safety_function_comparison/audit.ml>) reviews
checked authored implementations and discloses generated Dune-wrapper exclusions.
Dependencies are the existing compiler-matched lint engine, Paths, Artifact and
fs-read capability, with no new runtime dependency.
