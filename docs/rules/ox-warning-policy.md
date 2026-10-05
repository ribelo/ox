# ox-warning-policy

Compiler warnings are part of the safety boundary (^safe-tpzm, ^safe-y047).
Disabling a required warning, or making it nonfatal, is a finding. Restore the
compiler guard rather than adding `ox.allow`; this rule is not waiver-eligible.

## Pinned policy, not all warnings

The actual root declares Dune language 3.21 and no OCaml `env` override. Fresh
compiler commands from pinned Dune 3.22.2+ox pass `-warn-error +a` and no `-w`.
The required active set is therefore the linked OxCaml 5.4.0+ox compiler's
`Warnings.defaults_w`; only those active warnings are required to remain fatal:

```text
+a-4-7-9-27-29-30-32..42-44-45-48-50-60-66..70-74-183..184
```

Available but inactive warnings are not required or fatalized by this rule.
Required active and fatal sets are kept separate. A scanned override, including
a consumer's different Dune language declaration, never lowers this protected
root baseline. The warning universe and named spellings come from the linked
compiler's `Warnings.descriptions`, not a fabricated warning inventory.

Numeric, range, letter-group and named spellings are compared by effective meaning.
Ordered options and combined restoration are supported: `-w -P -w +8` and
`[@@@ocaml.warning "-P+8"]` preserve the required guard. Both unprefixed and
`ocaml.` source attributes (`warning`, `warnerror`) are checked in implementations
and interfaces. Floating attributes preserve order within their structure/signature;
attached attribute lists are evaluated in reverse AST order, matching the pinned
compiler's `Builtin_attributes.warning_scope`. Nested structures restore the
outer floating state. Compiler validation temporarily changes compiler warning
state and restores it on both success and failure.

## Supported targeted suppressions

The audited codec helper emitter supplies `-32` for generated unused-value
helpers. Existing canonical compiler-lint controls use `-32-34-37` for intentional
unused value/type/constructor declarations demonstrating another rule. The real
root active baseline already disables 32/34/37: these controls do not weaken it.
Their structural reasons are generated helper declarations and finite canonical
compiler-lint evidence, respectively; no filename exception, path waiver, or
blanket warning suppression is added. Preprocessor-synthesized attributes are
not independently parsed here: inspection follows the provenance-resolved authored
source, with the audited inactive helper suppression as the known generated case.
Disabling all warnings is forbidden. Disabling warning 8 (partial matches), 26
(unused local bindings), or 216 (use during borrowing) remains a finding.

## Finite evidence horizon

The dynamic typed callback receives the checked `Artifact.t`. It checks that exact
artifact's recorded `cmt_args`, then its provenance-resolved authored source, then
ancestor `dune` declarations up to the nearest `dune-project`. Reads require only
`fs_read`. Only regular policy files are read; a directory named `dune` is not
a policy file. Source attributes are parsed without constructing a compiler
environment or resetting the checked artifact's load path and implicit opens.
Missing args, argument files, nonliteral source attributes, missing
source/provenance and unreadable policy are named undecided, never clean.

Default-wrapped Dune empty main interfaces have an additional finite proof:
empty checked Typedtree, exact generated body, matching source digest, literal
test/executable producer and matching compiler output/unit ownership. The actual
physical interface is parsed; its logical source identifies the owning Dune stanza.
Stale generated bodies and unsupported producer/unit ownership remain failures,
and recorded arguments and current owning flags are still checked.

Supported Dune OCaml fields are `flags`, `ocamlc_flags` and `ocamlopt_flags`.
For a matching compiled library/test/executable in the source directory, literal common
and matching compiler-specific fields are reconciled against effective active/fatal
settings from its recorded compiler command. The real `dune-project` language
selects the audited dev common `:standard` for reconciliation only:

- 3.21 and 3.22: `-warn-error +a` (verified compiler commands).
- 3.20: `-w @1..3@5..28@31..39@43@46..47@49..57@61..62@67@69-40`.

These are the pinned Dune source's language-dependent defaults, not one global
standard. Other project-language versions are named unverified. Compiler-specific
`:standard` is empty. Bare dev consumers at the root language preserve the guard;
a bare legacy 3.20 consumer is a genuine restriction if its finite fatal set
weakens required root warnings. Explicit `-warn-error +a` restores that legacy
consumer without changing the production root. File timestamps are never policy
evidence. Comment or unrelated non-policy stanza edits preserve
agreement; changed warning content cannot borrow old metadata, even with preserved
timestamps. Templates, included flag files and unresolved ordered sets remain
unverified. Bytecode metadata does not certify native-only settings. Literal
library/executable names proved disjoint from the checked compiler `-o` object
scope are ignored, including unrelated libraries with their own warning flags.
Foreign C/C++ compiler/linker flag subtrees are not OCaml warning policy, including
foreign include-based ordered sets; they cannot alter the checked OCaml settings.
Unknown ownership, alternate or unbuilt profiles, Dune includes/subdirectory
inheritance and unavailable policy stay named unverified. A dev annotation cannot
certify an unbuilt release profile. No general Dune interpreter is introduced.

## Evidence and integration

The pure predicate tests are outside the nested negative project. Negative compiled
programs are declared inside their own project, not ordinary live corpus.
The installation test requires explicit `BIN` (installed executable), `SHARE`
(installed `share/ox_lint` root), `OCAMLC`, `CMI` and `DUNE` absolute paths.
It verifies all ancestors of the canonical installed prefix and share root, then
creates a consumer and a distinct invocation directory under `/var/tmp`, each with
all ancestors checked for `.git` files, directories or symlinks. It
uses installed canonical fixtures and `--self-check --root "$SHARE"`, then checks
actual compiled restrictions, restoration, unbuilt-profile uncertainty and missing
evidence. There is no checkout or Git fallback.

Registration, canonical annotation dependencies, the exact module manifest and
installed rule-page/fixture evidence are part of the ordinary lint integration.
The registered CLI regression also covers an ancestor directory named `dune`,
full-rule executable load paths, original-source freshness, disjoint library
flags, generated empty-interface producer/body/owner controls, foreign compiler
flags, and both sides of the audited Dune language-standard transition. These proofs
run from the owned ordinary `runtest` alias. Direct typed-annotation negative
controls avoid the Dune inventory query repairing deliberately corrupted generated
bodies before the checker runs.
