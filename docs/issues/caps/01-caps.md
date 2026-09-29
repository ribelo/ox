---
status: ready-for-agent
package: eta_caps (new), eta_app (Door mints the powerbox), every consumer
consumer: Leash first, then Pie, nema, inn, grip
---

# Capabilities: a function's type says what it may touch

## Problem Statement

Every line of Eta and its consumers is written by agents. Today nothing stops a slice deep in a service from calling `Unix.system`, `Unix.fork`, `Stdlib.exit`, `Sys.getenv` or opening a file: the type of a function says nothing about what it can do. Eio already treats I/O this way — `net`, `fs`, `process_mgr`, `clock` are values passed down — but the standard library's dangerous calls sit outside that discipline. ocaml-caps (Yoann Padioleau, OCaml Workshop 2026) generalises Eio's idea with object row types: `val f : < Cap.fork; Cap.network; .. > -> …`, capabilities forgeable only by `main`, plus Semgrep rules forbidding the raw calls. Rolled out on four 20–100k-line codebases in hours each; its author's strongest case is agent-written code, where a reviewer can trust the interface.

## Solution

`eta_caps`: our own copy of the caps idea (the library is tiny; owning it avoids a dependency and lets us align it with Eio's values), minted once by the Door as a powerbox alongside Eio's environment, narrowed by each program and passed to services as the specific capabilities they need; `Cap*` wrappers for the dangerous standard-library calls; Semgrep rules as a gate in every consumer forbidding the raw calls. Leash is the proving ground.

## User Stories

1. As a service author, I want abstract capability types for `fork`, `exec`, `exit`, `chdir`, `env`, `signal`, `time`, `random`, `stdin`, `stdout`, `stderr`, `fs_read`, `fs_write`, `tmp`, `network`, composed as object row types (`< Cap.exec; Cap.network; .. >`), so that a function's signature lists what it may touch. ^ncaps-sojd
2. As a service author, I want the only constructor of capabilities to be the Door: `Eta_app.run` hands the program a powerbox `< all_caps; .. >` next to Eio's env, and a test entry that mints a powerbox for tests, so that capabilities cannot be forged in library code. ^ncaps-0mvw
3. As a service author, I want `Cap_unix`, `Cap_sys`, `Cap_stdlib` modules wrapping the dangerous calls (`fork`, `system`, `open_process*`, `exit`, `chdir`, `getenv`, `open_in`/`open_out`, `Random.self_init`, `Unix.time`…) each requiring its capability, so that the safe variant exists for every raw call the rule forbids. ^ncaps-4btv
4. As a maintainer, I want a Semgrep rule set (`caps.yaml`) forbidding the raw calls in library and application code, with a documented allow-list for the wrappers themselves and for tests, so that the discipline is enforced, not hoped for. ^ncaps-n6r0
5. As a maintainer, I want the rule run as a gate (`dune build @caps` or a script the gates call) in Eta and every consumer, failing the build on a violation, so that an agent's slice cannot land a raw call. ^ncaps-w6n2
6. As a service author, I want Eio's own capabilities (`net`, `fs`, `process_mgr`, `clock`, `domain_mgr`) to remain Eio values passed as they are today, with `eta_caps` covering only what Eio does not wrap, so that there is no second copy of Eio's discipline. ^ncaps-jkku
7. As a service author, I want each Eta library to declare in its interface which capabilities it needs (`eta_process` needs `fork`+`exec`; `eta_ipc` needs `fs_write` for its socket; `eta_otel` needs nothing beyond Eio's `net`), so that a consumer knows what it grants by using a library. ^ncaps-x7z8
8. As a maintainer, I want Leash migrated first: `Chrome` receives `< Cap.fork; Cap.exec >`, `Control` and `Tabs` receive none, the Door mints the powerbox, and `leash` builds with the caps gate green, so that the discipline is proven on the largest agent-written service. ^ncaps-4tjy
9. As a maintainer, I want the migration of Pie, nema, inn and grip as follow-up rows sized after Leash's, with the count of annotations recorded (caps reports 50–500 per codebase), so that the cost is known before it is spent. ^ncaps-21nk
10. As a maintainer, I want the v1 reason for abandoning object capabilities recorded — objects are not `portable` across OxCaml domains — with the consequence that a capability must be minted per domain if a future `eta_par` consumer crosses domains, so that the constraint is known and not rediscovered. ^ncaps-vlwm
11. As a maintainer, I want a short guide `docs/caps.md`: how to narrow a powerbox, how to add a capability, how to add a wrapper and its rule, and how to read a violation, so that agents learn the discipline from one page. ^ncaps-xzx5
12. As a maintainer, I want the `AGENTS.md` of Eta and each consumer to state the rule in one line ('dangerous calls go through `Cap_*` and require a capability in the signature'), so that the rule is in the file agents read first. ^ncaps-2ydl
13. As a maintainer, I want a test that a function requiring `Cap.exec` cannot be called from a program whose powerbox was narrowed to exclude it (a compile-failure test, as `test/modes` does for portability), so that the type-level guarantee is pinned. ^ncaps-aw5n
14. As a maintainer, I want the choice 'own copy vs depend on ocaml-caps' recorded in ADR-0007 with the reason (alignment with Eio values, ~200 lines, single maintainer upstream), so that the dependency policy stays explicit. ^ncaps-iirv

## Implementation Decisions

- `eta_caps` is a small package with one module of abstract types and row aliases, the `Cap_*` wrapper modules, and the Semgrep rule file shipped under `caps/`.
- The Door's powerbox is an object; narrowing is by type ascription. Capabilities are single-domain values (story 10).
- The gate is a script running `semgrep --config caps/caps.yaml --error` over `lib/`, `packages/`, `bin/`, excluding the wrapper modules and `test/`; consumers copy the script or call Eta's.
- Leash's migration is its own commit series; each other consumer is a row when scheduled.

## Testing Decisions

- Seam: the gate itself on fixture files with and without violations; compile-failure tests for forged and excluded capabilities (`test/caps`, after `test/modes`); Leash's existing suites unchanged after its migration.

## Out of Scope

Capabilities for Eio's own values (already values); runtime capability checks; cross-domain capability transfer; wrapping every stdlib function (only the dangerous ones the rule names).

## Further Notes

Whether to depend on ocaml-caps or own a copy: the operator leans to owning it given its size; story 14 records the decision when made. The Semgrep OCaml support must be verified on this tree before story 5 (semgrep is installed on the machine).
