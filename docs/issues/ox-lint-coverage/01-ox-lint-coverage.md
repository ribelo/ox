---
status: ready
package: ox_lint
consumer: Ox and every consumer
---

# Every tracked source has a scan decision

## Problem Statement

The build inventory is enforcement: an omitted source receives no rule decisions. Tests, empty source directories and ignored build mirrors have each exposed an inventory defect in a consumer rather than in Ox. A clean findings count cannot prove coverage. The descriptor-duplication and dormant-concurrency decisions also need explicit, tested boundaries.

## Solution

Compare the engine's per-path inventory with an independent Git-tracked source baseline; test adversarial Dune layouts and fail on missing typed evidence rather than silently excluding a compiled module. Explain descriptor possession separately from ambient standard-descriptor acquisition. Keep raw concurrency deliberately inactive until its real replacements exist.

## User Stories

1. As a kernel maintainer, I want a test comparing every Git-tracked `.ml` and `.mli` with the actual scan decisions and named structural exclusions, so that omission by directory discovery or Dune membership fails in Ox before a consumer finds it. The checkout `scripts/caps-gate` runs this live-workspace census after the engine, reuses that run's inventory without a second scan or rebuild, and fails when either account fails. A `decided` record may have an empty reason; exclusions and undecided records must name theirs. ^nlintcov-8g4p
2. As a kernel maintainer, I want adversarial fixtures for test stanzas, byte-and-native executables, private modules, qualified subdirectories, copied/renamed modules, nested or vendored projects, symlinked sources, source-less generated modules, packages without interfaces, stale annotations and preprocessed output, so that each source is decided or excluded for a named structural reason. A default whole-repository gate finishes inventory, rebuilds `@check` once per workspace, discloses that rebuild and then consumes evidence without another inventory query; explicit scans never repair supplied stale/missing evidence. Dune 3.22 rule descriptions force volatile `(deps (universe))` producers, and neither alias-free nor targeted queries offer a non-building alternative. Source/import digests remain strict; staleness surviving the rebuild names its producer and remains undecided. ^nlintcov-q6n2
3. As a capability reviewer, I want the `Unix.dup` and `dup2` decision stated with the authority already held by the caller and the special case of process standard descriptors, so that descriptor-table mutation is not mistaken for either a new filesystem open or harmless duplication. ^nlintcov-d9u5
4. As a kernel maintainer, I want `ox-raw-concurrency` explicitly dormant, with the activation condition stated and CLI tests for default and explicit rule selection, so that no current policy pretends unavailable replacements can be enforced. ^nlintcov-r3k8

## Verification

The cross-check consumes the engine's `--inventory` output, not another reconstruction of its file walker. The default scan starts at the whole workspace: a fixed `lib`/`test` root list hid the real `bench/correlator_alloc.ml` executable and must not return. Named exclusions are checked against independent structural evidence: a nearer `dune-project`, or declared Dune data/module selection. An unknown or stale typed result is not an exclusion. The census reports the hole and undecided counts even if the strict scan fails.

The 63 tracked OCaml files below `docs/issues/*/spike/` and `evidence/` are historical experiments, frozen consumer snapshots and documentation snippets, not Ox build targets. No `dune` stanza exists anywhere below `docs`; the independent test asserts both this fact and the narrow spike/evidence boundary. Each must still receive an actual engine inventory entry, excluded as `not-built` or `data-only`; the latter additionally requires the independent root `(data_only_dirs docs)` declaration (these files are also consumed by the capability fixtures' `source_tree` dependency). Omission, a decided result or an undecided result fails the census. They are named documentation evidence, not a blanket “outside default roots” exemption; new OCaml elsewhere must receive an engine decision.

Run the independent census after the scanner and workspace annotations have been built, **outside** any Dune invocation holding that workspace:

```sh
python3 test/lint/deployment/coverage.py _build/default/lib/ox_lint/main.exe .
```

`scripts/caps-gate` runs the same census automatically after the engine. `--inventory-file FILE` writes the engine's ordinary `--inventory` records without changing its normal stdout/stderr. The census accepts `--inventory FILE --scan-exit CODE` together to consume those just-produced records and the directly captured engine status, instead of scanning again. This does not change the named exclusions or weaken failure validation. Help does not scan the workspace and retains its existing behaviour; `--self-check` in gate mode also scans and is cross-checked. Engine failures retain their exit code; a census failure makes an otherwise clean gate fail. ^nlintcov-8g4p

The first argument is the built scanner executable; the second is any directory inside the Git workspace. Paths are resolved before the scanner starts at the Git root. `--help` prints this contract and an example. Stdout contains one summary of tracked sources, decisions, named exclusion counts, coverage holes and undecided sources. Stderr contains validation errors and the scanner diagnostics on failure. Exit 0 means complete strict coverage and zero findings; exit 1 means a coverage, decision or strict-scan failure; exit 2 means invalid arguments or unavailable setup (Git/workspace/executable). The scratch-workspace adversarial fixtures remain in `dune runtest`; the live-root census does not, because recursively querying the enclosing Dune workspace would contend for its builder lock.

Real generated `.ml` and `.mli` compile inputs are inspected even without a source-tree counterpart. Findings name the source rule, `copy_files` stanza or executable/test stanza that owns an implicit empty interface. Unresolved producer provenance and failed compilation-inventory queries are named undecided. Raw PP declarations are retained, so an implicit interface compiled directly as `.pp.mli` is not replaced by a nonexistent `.mli` guess. Compiler-generated `.ml-gen` alias wrappers are not authored module inputs.

A nested project is a separate default scan boundary, not necessarily a separate evidence workspace. A nested project compiled by an outer Dune invocation owns no separate build tree; `/workspace_root` rebasing follows the annotation's actual `_build/default` owner. Explicit source and annotation arguments still inspect its evidence. Project-wide data-dependency traversal also stops at nested project boundaries; it cannot use another project's stanzas to exclude the parent's source.

`dup` copies held descriptor authority. `dup2` closes and rebinds a held destination, including process standard streams when its destination is 0, 1 or 2. It remains a descriptor operation, not a filesystem capability target; acquiring a raw standard descriptor requires the corresponding stdin/stdout/stderr capability.

## Out of Scope

Enabling the whole raw-concurrency rule before once-taking `Scope.fork`, `Spawner.t` and `Ox.Mutex` exist; new descriptor capability tokens; allow-list entries.
