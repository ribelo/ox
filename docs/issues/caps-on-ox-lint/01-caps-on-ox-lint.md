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

Depends on row 88. Both backends ran while equivalence evidence was gathered. After story 2’s recorded equivalence passed, the human authorized working-tree removal with this evidence in the same change; the human alone commits. Consumer development-shell edits remain separately authorization-gated.

The allow-list stays data, with its reasons, and keeps its current entries (the wrappers, the Door, the ppx driver, `ox-lint` itself). The `mint` rule keeps its three surfaces: the internal library boundary, the existing nonfatal compiler alert (making it fatal is outside this row) and the gate.

## Testing Decisions

`test/caps/gate/` keeps its fixtures and its pinned id-set, retargeted at the new rules; story 2's equivalence run is recorded in this spec with its numbers per repository, as row 75 recorded its census. A fixture per previously-unparsable file proves story 3.

## Recorded equivalence and removal evidence (2026-10-04)

^ncapslint-w2tq ^ncapslint-87ld ^ncapslint-ebh6: this evidence accompanies the authorized working-tree removal. Nothing was committed or staged. The five original consumer trees were read-only; all consumer builds and planted mutations were made in copies under `/tmp/ox-caps-row90/`. The old rules and gate were those in base `e1f9073457ba1080159330f356002476f17cafa9`; no shadow backend remains.

### Exact pinned set and copied-real-source mutation pairs

Both backends reported exactly the following 17 IDs on the pinned fixture. Both reported **18 findings and exit 1**: the extra occurrence is the second fork bearing an inline `nosemgrep` comment, deliberately not suppressed. The compiler run also named one typed-undecided fixture module; raw source coverage did not depend on its annotation.

| ID and rule page | Semgrep pinned occurrences | Compiler pinned occurrences | Copied mutation: Semgrep / compiler |
| --- | ---: | ---: | --- |
| [ox-caps-fork](<../../rules/ox-caps-fork.md>) | 2 | 2 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-exec](<../../rules/ox-caps-exec.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-exit](<../../rules/ox-caps-exit.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-chdir](<../../rules/ox-caps-chdir.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-env](<../../rules/ox-caps-env.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-signal](<../../rules/ox-caps-signal.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-time](<../../rules/ox-caps-time.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-random](<../../rules/ox-caps-random.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-stdin](<../../rules/ox-caps-stdin.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-stdout](<../../rules/ox-caps-stdout.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-stderr](<../../rules/ox-caps-stderr.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-fs-read](<../../rules/ox-caps-fs-read.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-fs-write](<../../rules/ox-caps-fs-write.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-tmp](<../../rules/ox-caps-tmp.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-network](<../../rules/ox-caps-network.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-mint](<../../rules/ox-caps-mint.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |
| [ox-caps-forge](<../../rules/ox-caps-forge.md>) | 1 | 1 | 1 finding, exit 1 / 1 finding, exit 1 |

Each mutation was a distinct copy of real [duration.ml](<../../../lib/ox/duration.ml>) with a never-evaluated raw operation appended at line 78. The expected rule ID was required in both outputs, not merely a nonzero exit. No original source was modified. The 17 pairs and pinned outputs are recorded under `/tmp/ox-caps-row90/mutations/<rule>/{semgrep,ox-lint}.txt` and `/tmp/ox-caps-row90/pinned/`.

### Six-tree mandatory-source census

Every in-scope source and interface was passed through the compiler parser, before any optional typed read. The old baseline had 0 findings and exit 0 in every repository, with the same scope and allowances. The final compiler census also has 0 findings and exit 0 in every repository. Ox requires typed evidence; the original consumers below were not rebuilt or mutated, so a source-clean exit is **not** a claim of complete typed coverage.

| Repository | Scope | Legacy findings / exit | Compiler findings / exit | Typed-undecided modules |
| --- | --- | --- | --- | ---: |
| ox | lib, plus bin if present | 0 / 0 | 0 / 0 (required typed) | 0 |
| leash | packages | 0 / 0 | 0 / 0 | 72 |
| pie | packages | 0 / 0 | 0 / 0 | 78 |
| nema | lib, bin | 0 / 0 | 0 / 0 | 3 |
| inn | lib, bin | 0 / 0 | 0 / 0 | 4 |
| grip | lib, bin | 0 / 0 | 0 / 0 | 17 |

Freshness checks reject source-digest mismatches, changed original/build copies, mismatched imported CMI fingerprints and compiler-incompatible evidence. The build precondition is `nix develop -c dune build @install` immediately before the gate, using the same compiler and dependency graph. All five copied consumers successfully built `@install`; that compatibility result cannot refresh annotations in their read-only original trees. The following diagnostics name **every** undecided original module and its reason (paths relative to that repository).

#### leash (72)

```text
packages/leash/actions.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/actions.pp.ml
packages/leash/actions.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/actions.mli
packages/leash/bin/cli_help.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/bin/cli_help.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/bin/cli_help.mli
packages/leash/bin/help_render.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/bin/help_render.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/bin/install_state.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/bin/main.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/bin/skill_install.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/cdp.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/cdp.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/chrome.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/chrome.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/chrome_stderr.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/chrome_stderr.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/config.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/config.pp.ml
packages/leash/config.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/config.mli
packages/leash/control.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/control.pp.ml
packages/leash/control.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/control.mli
packages/leash/desktop.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/desktop.ml
packages/leash/desktop.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/desktop.mli
packages/leash/dialog_race.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/discovery.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/discovery.pp.ml
packages/leash/dispatch.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/dispatch.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/download_setup.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/download_setup.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/drive.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/drive.ml
packages/leash/drive.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/drive.mli
packages/leash/expiry.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/expiry.pp.ml
packages/leash/expiry.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/jev_request.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/jev_request.ml
packages/leash/jev_request.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/jev_request.mli
packages/leash/learning.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/learning.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/leash.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/leash.ml
packages/leash/leash.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/leash.mli
packages/leash/model_error.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Leash__Model_error
packages/leash/model_usage.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/models.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/models.ml
packages/leash/models.mli:1: ox-lint: stale typed annotation: source is newer than annotation packages/leash/models.mli
packages/leash/net_log.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Leash__Net_log
packages/leash/page_kind.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/page_kind.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/planner.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/planner.pp.ml
packages/leash/planner.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/planner.mli
packages/leash/playbook.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/playbook.ml
packages/leash/playbook.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/playbook.mli
packages/leash/protocol.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/protocol.pp.ml
packages/leash/protocol.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/protocol.mli
packages/leash/public_suffix_data.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/public_suffix_data.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/questions.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/questions.ml
packages/leash/questions.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/questions.mli
packages/leash/reading.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/reading.ml
packages/leash/reading.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/reading.mli
packages/leash/run.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/run.pp.ml
packages/leash/run.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/run.mli
packages/leash/screenshot.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/screenshot.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/snapshot_dom.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Leash__Protocol
packages/leash/snapshot_source.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Leash__Protocol
packages/leash/tabs.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/leash/_build/default/packages/leash/tabs.pp.ml
packages/leash/tabs.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/tabs.mli
packages/leash/telemetry.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/telemetry.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/leash/text_helper.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/text_helper.ml
packages/leash/text_helper.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/leash/text_helper.mli
packages/leash/trace.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/trace.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/traces.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/leash/traces.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
```

#### pie (78)

```text
packages/pie/assistant/dictation.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant/dictation.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant/service.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant/service.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/client.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/client.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/contract.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/contract.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/server.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/assistant_service/server.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/audio/pcm.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/audio/pcm.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/audio/resampler.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/audio/resampler.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/bin/pie.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/bin/skill_cli.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/commands/meter.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/commands/record.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/commands/sources.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/config/stt.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/config/stt.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/desktop/notification.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/desktop/notification.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/desktop/notification_policy.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/desktop/notification_policy.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/embedded_prompts.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/fs.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/fs.ml
packages/pie/fs.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/fs.mli
packages/pie/glossary/glossary.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/glossary/glossary.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/history.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/history.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/input/text_injection.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/input/text_injection.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/keyboard/monitor.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/niri/niri.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/paths.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/pie/pie.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/pie.ml
packages/pie/pie.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/pie.mli
packages/pie/process.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/pie/ptt/capture.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/ptt/capture.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/ptt/dead_input.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/ptt/low_volume.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/ptt/low_volume.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/ptt_loop.ml:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/ptt_loop.ml
packages/pie/ptt_loop.mli:1: ox-lint: stale typed annotation: original source differs from build copy packages/pie/ptt_loop.mli
packages/pie/pulse/client.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/client.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/commands.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/commands.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/defs.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/defs.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/protocol.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/pulse/protocol.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/audio_archive.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/audio_archive.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/coordinator.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/coordinator.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/phase.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/retry_store.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/retry_store.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/state_writer.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/recording/state_writer.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/sh.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/pie/sh.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
packages/pie/stt/codex_realtime.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/codex_realtime.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/correction.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/correction.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/language.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/language.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/openrouter.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/stt/openrouter.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/wayland/clipboard.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/wayland/clipboard.mli:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/wayland/wtype.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
packages/pie/x11/xdotool.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
```

#### nema (3)

```text
bin/nema/cli_error.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
bin/nema/main.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
bin/nema/telemetry.ml:1: ox-lint: stale typed annotation: digest mismatch for /home/ribelo/projects/ribelo/nema/_build/default/bin/nema/telemetry.ml
```

#### inn (4)

```text
bin/main.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
lib/server.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/store.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/store.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
```

#### grip (17)

```text
bin/main.ml:1: ox-lint: missing typed annotation; run dune build @install with -bin-annot
lib/button.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/cli.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/config.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/config.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/daemon.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/device_discovery.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/device_discovery.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/engine.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/engine.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/executor.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/key.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/linux_input/linux_input.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/linux_input/linux_input.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/observability.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/profile.ml:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
lib/profile.mli:1: ox-lint: stale typed annotation: imported CMI fingerprint changed for Eio
```

### Classified extras and signature provenance

^ncapslint-8jcy: the initial implementation emitted **ten**, not twelve, false-positive signature diagnostics on legitimate argument authority. The earlier “twelve” figure was never supported by output. All ten were reviewed and fixed before removal:

| Repository | Initial diagnostic location | Classification |
| --- | --- | --- |
| ox | [listener.ml:94](<../../../lib/ipc/listener.ml#L94>), [listener.ml:307](<../../../lib/ipc/listener.ml#L307>) | enclosing argument captured by nested/local functions |
| ox | [sqlite.ml:711](<../../../lib/sql/sqlite.ml#L711>) | enclosing argument captured by a closure |
| nema | [skill_install.ml:58](</home/ribelo/projects/ribelo/nema/bin/nema/skill_install.ml#L58>), [skill_install.ml:168](</home/ribelo/projects/ribelo/nema/bin/nema/skill_install.ml#L168>) | legitimate argument capture |
| nema | [lifecycle.ml:280](</home/ribelo/projects/ribelo/nema/lib/nema/lifecycle.ml#L280>) | genuine typed-token dependency record argument |
| nema | [service.ml:129](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L129>) | argument-record authority; actual `runtime.caps` wrapper use at [line 202](</home/ribelo/projects/ribelo/nema/lib/nema/service.ml#L202>) is context, not an eleventh site |
| inn | [mcp.ml:687](</home/ribelo/projects/ribelo/inn/lib/mcp.ml#L687>) | legitimate argument capture |
| grip | [process.ml:19](</home/ribelo/projects/ribelo/grip/lib/process.ml#L19>), [process.ml:24](</home/ribelo/projects/ribelo/grip/lib/process.ml#L24>) | enclosing argument captured by closures |

**The capability must be in scope through an argument.** Nested, local, anonymous and returned closures may capture genuine enclosing argument authority; a genuine closed typed-token record argument and its field projections are also authority. Parameter identity uses `Ident.same`, and direct let aliases preserve provenance. A global/module token or a locally minted token does not become argument authority just because its type is correct.

The independent signature triangle proves all three negative sites in the compiled [violating fixture](<../../../test/caps/rules/violating/signature.ml#L3-L11>): ambient genuine token (3), similarly named `< fork : int >` impostor (5), and locally minted token (9). [The clean fixture](<../../../test/caps/rules/clean/signature.ml>) proves visible arguments, enclosing captures/returned closures, genuine dependency records and direct aliases. Fresh typed positive/negative tests run separately from source findings, for all 17 raw rules and the signature rule.

In a copy of Grip, the planted well-typed violation was a global `Ox_caps.Cap.time` token followed by a no-argument function calling `Ox_caps.Cap_unix.gettimeofday ~caps:row90_ambient ()`. Its copied `@install` build succeeded; selecting only `ox-caps-signature` emitted the expected finding at `lib/process.ml:56` and exited 1. This is a new real violation, not a tolerated census extra. The never-evaluated planted code stayed under `/tmp/ox-caps-row90/consumers/grip/`.

Limits: this is direct resolved raw-reference/wrapper checking, not a transitive call graph. Higher-order calls through an unknown argument, opaque re-exports/functors without fresh typed evidence and arbitrary helper-mediated authority flow are not proven. The rule tests genuine argument capability exposure for raw references, but does not prove that every possible path consumes the particular exposed token. Complex local transformations are not provenance analysis; generic record-field parameter substitution is not implemented and may conservatively reject such record authority. These limits are not silently replaced by spelling heuristics.

Independent typed tests exposed a real `chdir` miss: `Env.initial` does not resolve implicitly opened `Stdlib` submodules through bare `Sys`/`Random` names. Targets now include explicit `Stdlib` prefixes for `Sys`, `Random`, `Scanf`, `Printf`, `Format`, `In_channel`, `Out_channel`, `Filename` and `Obj`; normalized compiler paths and `Path.same` remain the equality test. All 17 independent typed negative fixtures now fire, rather than allowing a source result to mask a typed miss.

### Six measured parser holes and protection limits

^ncapslint-5rxe: the legacy Semgrep JSON reported the following six Ox files as `PartialParsing` (208 spans total, including repeated spans). This describes unsupported **fragments**, not proof that all 17 rules were disabled over each entire file; supported fragments remained eligible for normal matching. No actual missing violation is inferred from a clean partial parse.

| Original file | Reported spans | Grammar | Minimized compiler-source regression and expected rule |
| --- | ---: | --- | --- |
| [server.ml](<../../../lib/http/server.ml#L481>) | 1 | record coercion shorthand | [server.ml](<../../../test/caps/rules/holes/server.ml>): `ox-caps-network` |
| [ws_client.ml](<../../../lib/http/ws_client.ml#L262>) | 1 | record coercion shorthand | [ws_client.ml](<../../../test/caps/rules/holes/ws_client.ml>): `ox-caps-stdout` |
| [schedule.mli](<../../../lib/ox/schedule.mli>) | 7 | `@@ portable` modes | [schedule.mli](<../../../test/caps/rules/holes/schedule.mli>): `ox-caps-mint` via a Door module alias |
| [sqlite.ml](<../../../lib/sql/sqlite.ml>) | 159 | portable mode bindings/types | [sqlite.ml](<../../../test/caps/rules/holes/sqlite.ml>): `ox-caps-fork` |
| [types.ml](<../../../lib/sql/types.ml>) | 29 | local-mode function types | [types.ml](<../../../test/caps/rules/holes/types.ml>): `ox-caps-env` |
| [ox_sql_dsl.ml](<../../../lib/sql_dsl/ox_sql_dsl.ml>) | 11 | portable bindings/local parameters | [ox_sql_dsl.ml](<../../../test/caps/rules/holes/ox_sql_dsl.ml>): `ox-caps-forge` |

Within unsupported implementation fragments, syntax-driven rules for fork/exec/exit/chdir/env/signal/time/random/stdin/stdout/stderr/fs-read/fs-write/tmp/network/mint/forge had no reliable AST coverage; this does not mean each fragment contained every operation. On the interface-only scheduling file there are no runtime expression calls for those raw-operation rules to match: the meaningful independent protection is the Door module/type-reference boundary.

The old fallback extracted literal qualified/bare identifiers from **positive** YAML patterns and explicitly added mint/forge spellings, masked comments/strings and treated all partial/skipped files lexically. It therefore still caught literally spelled targets across those files, with some special entry-point/stream-binder exclusions; it could not establish `open Unix` bare `fork`, renamed aliases, opaque module identity or genuine token/signature provenance. The separate old Door check protected literal `Ox_caps_door` module/type references and the Dune dependency boundary, not arbitrary identity-preserving re-exports. The new compiler source tier handles the minimized grammar and lexical-binding cases; fresh typed evidence supplies external identity/signature coverage. Source-only parser regressions do not claim a whole-program capability proof.

Exact measured span ranges (duplicates retained):

```text
lib/http/server.ml: 481
```

```text
lib/http/ws_client.ml: 262
```

```text
lib/ox/schedule.mli: 1, 32–69, 81–83, 83–124, 124, 126–157, 157
```

```text
lib/sql/sqlite.ml: 1–65, 108, 110, 137, 137, 145, 165, 167, 173, 175, 179, 181, 181, 185, 187, 189, 189, 193, 193, 199, 199, 203, 205, 209, 211, 215, 218, 222, 224, 224, 228, 230, 230, 234, 237, 237, 241, 243, 243, 247, 249, 249, 253, 255, 255, 259, 261, 265, 267, 267, 271, 274, 274, 278, 285, 287, 287, 291, 294, 294, 298, 300, 300, 304, 307, 311, 314, 314, 318, 320, 320, 324, 327, 327, 331, 334, 338, 339, 343, 344, 348, 351, 355, 358, 362, 365, 365, 368, 371, 374, 377, 381, 384, 384, 387, 390, 394, 395, 395, 398, 401, 401, 404, 406, 410, 412, 434, 437, 439, 439, 443, 443, 446, 446, 458, 461, 461, 463, 509, 509, 515, 515, 521, 530, 530, 543, 551, 551, 554, 557, 557, 559, 562, 562, 564, 587, 589, 592, 594, 597, 599, 602, 604, 608, 610, 614, 617, 620, 622, 626, 628, 632, 635, 638, 641, 644, 665, 690, 692
```

```text
lib/sql/types.ml: 27, 96, 100, 100, 105, 116, 116, 116, 125, 125, 134, 134, 134, 135, 135, 144, 144, 144, 168, 168, 181, 181, 183, 192, 192, 195, 195, 208, 208
```

```text
lib/sql_dsl/ox_sql_dsl.ml: 66, 66, 74, 74, 80, 82, 82, 82, 166, 228, 231
```

Leash additionally had partial parses in `packages/leash/drive.ml`, `packages/leash/learning.ml` and `packages/leash/traces.ml`; Pie, nema, inn and grip had no parser-hole baseline. Every final selected source in all six trees was successfully compiler-parsed.

### Allowances, installed compatibility and authorized removal

^ncapslint-x3gi ^ncapslint-snhg: `scripts/caps-gate` retains its name, glob/directory allowance semantics and exact four policy entries. The tool checks this table in [caps.md](<../../caps.md>) against policy data in both directions, rejects missing/changed/extra/duplicate entries, and preserves test exclusion and entry-point exceptions. Absolute and dot-qualified paths within the invocation root now use the same policy identity as relative paths; lexical parent segments cannot widen a protected boundary. Installed regression tests cover absolute mint entry/library paths, absolute Door dependency paths and absolute paths with relative allowances.

| Ox allowance | Reason |
| --- | --- |
| `lib/caps` | The Cap_* wrappers and token identity boundary contain the raw calls. |
| `lib/app/ox_app.ml` | The Door mints the powerbox, reads the environment and installs process signal handlers. |
| `lib/ppx_yojson_minimal/main.ml` | Build-time preprocessor: reads source, writes stdout and exits; not a Door program. |
| `lib/ox_lint` | Compiler build tool: reads sources and typed evidence, writes CLI output and status; not a Door program. |

Consumer allowance data was not changed: Leash allows `packages/leash/bin/gen_skill_data.ml` and `packages/leash/bin/gen_error_topic.ml` (build-time data generators); nema allows `bin/nema/gen_skill_data.ml` (build-time skill generator); Pie, inn and grip have none.

The YAML configuration and the 384-line legacy Bash/Python backend were deleted; `caps-gate-semgrep` was also deleted rather than retained as a shadow. Only [the shell-readable installed launcher](<../../../lib/caps/caps-gate>) remains in `share/ox_caps`, forwarding to the adjacent `share/ox_lint/ox-lint` (or explicit `OX_LINT`). This preserves consumers’ `exec bash "$gate"` invocation. `ox_caps` now declares an exact-version, build-only `ox_lint` package dependency; it does not add a runtime library dependency. Ox’s Semgrep development-shell dependency is removed. The rule pages and both fixture sets are installed; source-checkout and relocated installed `--self-check` regressions cover missing evidence.

The installed gate contract is exit 0 for source-clean optional-typed runs (with every undecided file named), exit 1 for findings, exit 2 for parser/tool/evidence failures. `--require-typed` makes missing/stale/incompatible evidence fatal; Ox’s wrapper always supplies it. No lexical fallback or inline suppression remains. The existing Door compiler mint alert is preserved as nonfatal, demonstrated by the compiled local-mint regression; making it fatal is outside this change.

Consumer development shells are explicitly **deferred pending human authorization**, and remain untouched. Exact required changes, one per repository:

- Leash: remove explicit `pkgs.semgrep` from [flake.nix:311](</home/ribelo/projects/ribelo/leash/flake.nix#L311>); install/pin the compiler-matched exact-version `ox_lint` alongside `ox_caps` in its shared OPAM setup; build `@install` before the gate, retaining both generator allowances.
- Pie: [flake.nix](</home/ribelo/projects/ribelo/pie/flake.nix>) has no Semgrep dependency to delete; include/pin matching `ox_lint` in its shared OPAM Ox package setup ([line 214](</home/ribelo/projects/ribelo/pie/flake.nix#L214>)); build `@install` before the gate; no allowances.
- nema: [flake.nix](</home/ribelo/projects/ribelo/nema/flake.nix>) has no Semgrep dependency to delete; expose the compiler-matched `ox_lint` build-tool derivation and its installed share directory in the Nix development shell ([line 370](</home/ribelo/projects/ribelo/nema/flake.nix#L370>)); build `@install` before the gate, retaining its generator allowance.
- inn: [flake.nix](</home/ribelo/projects/ribelo/inn/flake.nix>) has no Semgrep dependency to delete; make compiler-matched exact-version `ox_lint` available with its shared OPAM Ox installation; build `@install` before the gate; no allowances.
- grip: [flake.nix](</home/ribelo/projects/ribelo/grip/flake.nix>) has no Semgrep dependency to delete; include/pin matching `ox_lint` in its shared OPAM Ox package setup ([line 220](</home/ribelo/projects/ribelo/grip/flake.nix#L220>)); build `@install` before the gate; no allowances.

The final read-only `.nix` census found explicit consumer Semgrep only in Leash, not in the other four repositories; “remove Semgrep from every consumer” therefore does not authorize inventing deletions where no dependency exists.

### Final direct gates

Each required command was run directly and sequentially after rebuilding with base `e1f90734`, with its immediate `$?` captured (`command; echo rc=$?`), never through a pipe into `tail`. Final exits after the last code and test changes:

| Direct command | Exit |
| --- | ---: |
| `nix develop -c dune build @install` | 0 |
| `nix develop -c dune test` | 0 |
| `nix develop -c dune build @fmt` | 0 |
| `nix develop -c scripts/caps-gate` | 0 |

The full test includes the independent source/typed rule triangles, all three compiled signature negatives, six parser-hole source regressions, all declared library modules and the relocated installed self-check and shell-readable installed gate. The strict Ox gate reports `0 findings; 0 modules with typed rules undecided (typed evidence required)`. Logs are under `/tmp/ox-caps-row90/gate-{install,test,fmt,caps}-final.txt`. `git diff --check` also exits 0.

## Out of Scope

Changing what any capability means; changing the `Cap_*` wrappers; row 89's documentation rules.
