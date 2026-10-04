# ox-discarded-result

Forbids discarding an expression whose inferred type is the standard two-parameter
`result` through `Stdlib.ignore` (including module aliases, opens, `@@` and `|>`)
or `let _ =`. Manifest type aliases are expanded; local functions named `ignore`
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

Or match `Ok` / `Error` and handle the failure. When handling it would change an
intentional best-effort policy, name the discard and explain that policy:

```ocaml
(* Closing is best effort; preserve the original operation's failure. *)
let _close_result = close connection in
original_result
```

A comment alone is not a suppression. Named discards are visible review decisions;
the check does not assess whether their reason is good.

## Check

Build first, then run the decider from the same Ox installation:

```sh
dune build @install
"$(opam var ox_lint:share)/ox-lint" --require-typed --rules ox-discarded-result lib/
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
- Value aliases are not followed: `let drop = Stdlib.ignore` then `drop result`
  is outside the rule, as is passing a discard function as an argument.
- For preprocessed input the annotation's digest covers the generated source.
  The engine also checks the original against Dune's build copy and its timestamp;
  manually preserving timestamps while replacing a symlinked build source is not
  a supported substitute for rebuilding.

The gate declares its required source modules in
[modules.txt](<../../test/lint/modules.txt>); it never infers coverage from annotations
that happen to exist. The rule's [violating](<../../test/lint/violating/discard.ml>) and
[clean](<../../test/lint/clean/discard.ml>) fixtures are checked under `test/lint/`.
Concurrency and interface-documentation rules belong to rows 88 and 89; the caps
gate remains independent. (^nlint-emql, ^nlint-4sct)
