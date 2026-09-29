---
status: ready-for-agent
package: ox_caps, scripts/caps-gate, ox_app
consumer: every consumer's caps gate
---

# Caps gate 2: no silent skips, minting only at the Door

## Problem Statement

Row 48's gate reports "skipped files" on every run: Semgrep cannot parse OxCaml mode syntax, and files it cannot parse pass silently. A security gate that passes what it did not read looks like proof and is not. Separately, `Cap.powerbox : unit -> all_caps` is public, so any library can mint every capability; only a Semgrep rule forbids it. Bare `stdout`/`stderr` channel values and file I/O inside libraries also escape the rules.

## Solution

The gate fails on any in-scope file Semgrep skipped, unless a token-level check (the same forbidden identifiers, matched lexically) passes on that file. Minting moves to an internal sub-library that only `ox_app` depends on, and the gate forbids depending on it anywhere else. The rule set gains bare channel values and library file I/O.

## User Stories

1. As a maintainer, I want `scripts/caps-gate` to parse Semgrep's JSON output and fail when any file in its scope was skipped for a parse error, naming the file, so that an unreadable file can never pass. ^ncaps-a27b
2. As a maintainer, I want each skipped file checked instead by a lexical scan for the same forbidden identifiers (`Unix.fork`, `Sys.command`, `Stdlib.exit`, `open_in`, …, as the rule file lists them) with the same allow-list, passing only if the scan finds nothing, so that OxCaml-syntax files are still covered. ^ncaps-tpjy
3. As a maintainer, I want the full-powerbox constructor moved into an internal library (`ox_caps.door`) that only `ox_app` and the test entry depend on, and a gate check that fails if any other dune file lists it, so that minting outside the Door requires an edit the gate rejects. ^ncaps-uiq6
4. As a maintainer, I want rules for bare `stdout`/`stderr`/`stdin` channel values and `In_channel`/`Out_channel` file functions in library code, each with a `Cap_*` wrapper, so that the gaps row 48 reported are closed. ^ncaps-znyh
5. As a maintainer, I want fixture files proving each case: an unparseable file with a forbidden call fails, the same file without one passes, a dune file depending on `ox_caps.door` outside ox_app fails, a bare `stdout` fails, so that the gate's behaviour is pinned. ^ncaps-rwnz
6. As a maintainer, I want every consumer's gate script replaced by ox's (called with the consumer's paths), Leash's live acceptance run once after the caps threading with its result recorded here, so that one gate exists and caps is proven against real Chrome. ^ncaps-mygj

## Implementation Decisions

- `semgrep --json`; skipped paths under `paths.skipped` with a parse-error reason; the lexical scan is a small script over the rule file's patterns.
- `ox_caps.door` is a dune sub-library; its only export is the powerbox constructor.

## Testing Decisions

- Gate fixtures under `test/caps-gate/` run by the gate's own test; Leash's live gate (story 6).

## Out of Scope

Compiler-enforced minting; stack-local capabilities; consumers' own caps conversions (rows 50–53).
