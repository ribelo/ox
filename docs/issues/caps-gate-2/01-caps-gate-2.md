---
status: completed
package: ox_caps, scripts/caps-gate, ox_app
consumer: every consumer's caps gate
---

# Caps gate 2: no silent skips, minting only at the Door

## Problem Statement

Row 48's gate reports "skipped files" on every run: Semgrep cannot parse OxCaml mode syntax, and files it cannot parse pass silently. A security gate that passes what it did not read looks like proof and is not. Separately, `Cap.powerbox : unit -> all_caps` is public, so any library can mint every capability; only a Semgrep rule forbids it. Bare `stdout`/`stderr` channel values and file I/O inside libraries also escape the rules.

## Solution

The gate fails on any in-scope file Semgrep skipped, unless a token-level check (the same forbidden identifiers, matched lexically) passes on that file. Minting moves to an internal sub-library used by `ox_app` and the test entry (with `ox_caps` depending on its abstract token types), and the gate forbids other dependencies or source references. The rule set gains bare channel values and library file I/O.

## User Stories

1. As a maintainer, I want `scripts/caps-gate` to parse Semgrep's JSON output and fail when any file in its scope was skipped for a parse error, naming the file, so that an unreadable file can never pass. ^ncaps-a27b
2. As a maintainer, I want each skipped file checked instead by a lexical scan for the same forbidden identifiers (`Unix.fork`, `Sys.command`, `Stdlib.exit`, `open_in`, …, as the rule file lists them) with the same allow-list, passing only if the scan finds nothing, so that OxCaml-syntax files are still covered. ^ncaps-tpjy
3. As a maintainer, I want the full-powerbox constructor moved into an internal library (`ox_caps.door`) that only `ox_app` and the test entry depend on, and a gate check that fails if any other dune file lists it, so that minting outside the Door requires an edit the gate rejects. ^ncaps-uiq6
4. As a maintainer, I want rules for bare `stdout`/`stderr`/`stdin` channel values and `In_channel`/`Out_channel` file functions in library code, each with a `Cap_*` wrapper, so that the gaps row 48 reported are closed. ^ncaps-znyh
5. As a maintainer, I want fixture files proving each case: an unparseable file with a forbidden call fails, the same file without one passes, a dune file depending on `ox_caps.door` outside ox_app fails, a bare `stdout` fails, so that the gate's behaviour is pinned. ^ncaps-rwnz
6. As a maintainer, I want every consumer's gate script replaced by ox's (called with the consumer's paths), Leash's live acceptance run once after the caps threading with its result recorded here, so that one gate exists and caps is proven against real Chrome. ^ncaps-mygj

## Implementation Decisions

- `semgrep --json`; skipped paths under `paths.skipped` with a parse-error reason; the lexical scan is a small script over the rule file's patterns.
- `ox_caps.door` is a Dune sub-library. It seals the concrete token types and exports one constructor, `Ox_caps_door.powerbox`, marked with the `mint` alert. `Cap.Token` re-exports manifest aliases of those abstract types, so the constructor type-checks at the Door without exposing token constructors. `lib/caps/dune` depends on the sub-library for those types; `lib/app/dune` and `lib/test/dune` are the only mint callers. The gate rejects other direct Dune dependencies and source references to `Ox_caps_door` (including through transitive library visibility).

## Testing Decisions

- Gate fixtures under `test/caps/gate/` run by the gate's own test; Leash's existing headless live gates run after a private Ox install (story 6).

## Acceptance evidence (2026-09-29)

- Ox: isolated `_build_r54b` `dune build @install`, `dune test` and `scripts/caps-gate` passed, including the skipped-file lexical fallback and door-dependency fixtures. `dune build @fmt` currently fails only on the gate worker’s new exact-line-number fixtures under `test/caps/gate/`; that worker’s owner will exclude them from formatting and rerun it. Leash resolves the installed Ox gate through `ocamlfind query ox_caps`, with no local override.
- Leash: isolated `_build_r54b` `dune build @install`, `dune test`, `dune build @fmt` and its installed-Ox `scripts/caps-gate` passed. Its gate reported two Semgrep partial parses (`drive.ml`, `run.ml`) and lexically scanned both, with zero findings.
- Leash headless live gates after caps threading: base, m2, m3, m4, m5, m8, m8b, m9 passed. The m4 notifier warning race needed a bounded harness wait; m5 used the current `drive MISSION --tab TAB` CLI and `operator_steps`. The m7 discovery phase and the m9b/m9c no-model test phases passed.
- m9b model missions passed: Mystery category 32 records and under-£20 subset 10, matching independently counted site records; m9c passed Travel 11, Fiction 65 and Default 152, each matching the site. Both gates confirmed headless Chrome exit and no API key leak.
- m7 cross-site phase passed separately: GitHub public PDF download followed by Example Domain, two verified procedures, `done` without planner or duplicate action (7.2 s); both mission checks passed, the final Chrome title contained `Example Domain`, one completed PDF download remained, and Chrome exited. Before the run-loop fix, it redundantly verified Example repeatedly then timed out. Two scripted `ncaps-mygj` regressions now pin automatic DONE and the unchanged-page duplicate guard.
- The original m7 text expectation `the page shows Example Domain` was correctly false on the **current** example.com body: live `leash text` began “This domain is for use in documentation examples…”, the DOM had no `h1`, and `document.title` was `Example Domain`. The gate now requires the installed `the page is example` checker and separately asserts the Chrome title; a checker regression pins the distinction between title and body. This is live site drift, not a change to the body-text rule.
- The complete m7 `all` attempt remains **red** at the separate Automation Exercise shopping fallback: a new `adpub-drawer-root` overlay covered the search button and View Product target, so refusing to click through it was correct. It stopped after 238.4 s and did not reach the cross-site portion of that combined run; the independently run cross-site phase above is green. **Follow-up:** extend the Automation Exercise example playbook with an ad-overlay page kind and dismiss procedure, analogous to its L34 consent recovery, then rerun m7 `all`. No headed/operator gate was run.

## Out of Scope

Compiler-enforced minting; stack-local capabilities; consumers' own caps conversions (rows 50–53).
