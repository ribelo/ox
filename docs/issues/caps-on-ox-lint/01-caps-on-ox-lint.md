---
status: ready
package: ox_lint (rules), ox_caps, scripts/caps-gate, flake (dev shells)
consumer: Ox and every consumer: one decider, one language
---

# The capability rules move onto `ox-lint`; Semgrep leaves the tree

## Problem Statement

The capability gate is ox's security boundary and it is built from four languages and one external tool: 384 lines of bash with embedded Python, 17 rules as Semgrep patterns in `caps.yaml`, and Semgrep itself, whose OCaml support is Experimental by its own definition. Three consequences, all measured:

- **It degrades to grep exactly where it matters most.** Semgrep cannot parse OxCaml mode syntax, so `lib/ox/schedule.mli`, `lib/sql/sqlite.ml`, `lib/sql/types.ml` and `lib/sql_dsl/ox_sql_dsl.ml` fall back to a lexical identifier scan on every run. That fallback matches identifiers, not bindings: it cannot tell a local function named `exit` from `Stdlib.exit`, and it cannot see that `open Unix` made a bare `fork` into `Unix.fork`. Both directions of error are live — false alarms and **silent misses** — in the one gate whose job is to be trusted.
- **Name matching is not identity.** Row 87 measured the gap on this tree with the same kind of rule: 40 candidates by name, 8 real. `ox-lint` resolves `open`, module aliases and paths, and compares with `Path.same`.
- **The rules are about types, and Semgrep has none.** A capability rule says: this function touches the outside world, so its signature must name the capability. The current rules can only forbid the raw call; the property they are really about — a function that reaches a dangerous operation **without** `~caps:< Cap.x; .. >` in its type — is decidable on the Typedtree and inexpressible as a text pattern.

## Solution

Reimplement the 17 `ox-caps-*` rules as `ox-lint` rules, prove them equivalent-or-stronger on real trees before switching, then delete the Semgrep path and drop the dependency from the dev shells. The gate keeps its name, its contract and its fixtures; only the decider changes.

## User Stories

1. As a maintainer, I want all 17 `ox-caps-*` rules reimplemented as `ox-lint` rules, each resolving `open`, aliases and paths rather than spellings, so that a renamed or re-opened dangerous call cannot pass. ^ncapslint-nf4t
2. As a maintainer, I want an **equivalence gate as the entry condition**: on ox and on all five consumers (Leash, Pie, nema, inn, grip), `ox-lint` must report every finding Semgrep reports — not one fewer — and the switch is accepted only once every extra finding has been reviewed and is either a real violation Semgrep missed or a false positive fixed before the switch. The pinned id-set on `test/caps/gate/violating/` is the first half of this test. ^ncapslint-w2tq
3. As a maintainer, I want the four files that fall back to a lexical scan today checked **fully** by the new rules, with a test naming them, so that the hole this row exists to close is proven closed. ^ncapslint-5rxe
4. As a maintainer, I want the typed form of the rule added where it is now reachable — a function that reaches a dangerous operation without the matching capability in its signature — behind its own rule id, listed apart from the raw-call rules, with its false negatives stated (no interprocedural reasoning beyond the declared closure). ^ncapslint-8jcy
5. As a maintainer, I want `scripts/caps-gate` to keep its name, its `--allow` semantics with per-entry reasons, its `share` installation and its exit codes, so that no consumer changes how it runs the gate; internally it calls `ox-lint` and the bash and Python go. ^ncapslint-x3gi
6. As a maintainer, I want the lexical fallback **deleted**, not kept as a safety net: a file the engine cannot parse is a named failure, since the engine is the compiler's own parser and a parse failure now means something is genuinely wrong. ^ncapslint-87ld
7. As a maintainer, I want Semgrep removed from the dev shells of ox and of the consumers, and `caps.yaml` deleted, once story 2 passes — so that the gate has no external dependency and one rule set in one language. ^ncapslint-ebh6
8. As a maintainer, I want `docs/caps.md`'s rule table rewritten against the new ids with the same rule/fixture/page triangle `ox-lint --self-check` enforces, and the allow-list checked against its documentation by the tool rather than by eye. ^ncapslint-snhg

## Implementation Decisions

Depends on row 88: the concurrency rules go first, on ground where there is nothing to break, so the engine carries real traffic before it takes the security boundary. Until story 2 passes, **both gates run**; the Semgrep path is deleted in the same commit that records the equivalence evidence, never before.

The allow-list stays data, with its reasons, and keeps its current entries (the wrappers, the Door, the ppx driver, `ox-lint` itself). The `mint` rule keeps its three surfaces: the internal library boundary, the compiler alert made fatal (row 66 story 11) and the gate.

## Testing Decisions

`test/caps/gate/` keeps its fixtures and its pinned id-set, retargeted at the new rules; story 2's equivalence run is recorded in this spec with its numbers per repository, as row 75 recorded its census. A fixture per previously-unparsable file proves story 3.

## Out of Scope

Changing what any capability means; changing the `Cap_*` wrappers; row 89's documentation rules.
