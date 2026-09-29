---
status: completed
package: ox_caps (new; eta_caps before the rename), ox_app (Door mints the powerbox), ox_process, ox_test, every consumer
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

## Delivered

The guide is `docs/caps.md`; the API, the rules and what the gate cannot see are there. Decisions taken where the spec left room:

- Names follow the rename: `ox_caps` with `Ox_caps.Cap`, `Cap_unix`, `Cap_sys`, `Cap_stdlib`; the rules and the gate script are `lib/caps/caps.yaml` and `lib/caps/caps-gate`, installed under `share/ox_caps` so a consumer runs the version it builds against. Wrappers take `~caps` (labelled, like `~sw` and `~clock`), as an ordinary global argument: a `@ local` parameter made every partial application local (`docs/modes.md`).
- The Door mints in `run_for_test_with_args`, which every Door entry goes through, and `Ox_app.Env.t` gained the field `caps`. Commands get it through `commands_with_env` and the new `config_commands_with_env`; `Ox_test.powerbox` is the test entry. `Cap.powerbox` carries a `mint` alert; the `ox-caps-mint` rule is what refuses it.
- The gate is `scripts/caps-gate` in each repository, with `--disable-nosem` and `--no-git-ignore`, and its allow-list is only the `--allow` entries in that script. The one raw exit it allows is `exit (Ox_app.run ...)` — an entry passing the Door's code on.
- Story 7: `Ox_process.Child.spawn` takes `~caps:< Cap.fork; Cap.exec; .. >` now — Leash is its only user. `ox_ipc` (Pie), `ox_otel` (Pie, grip, inn, Leash), `ox_sql` (inn) and `Schedule.start`'s default random state declare their capabilities in their interfaces and are on ox's allow-list until the consumer rows 50–53: requiring them now would break consumers that are rebuilt whenever ox is installed into the shared switch.
- Story 8: Chrome receives `< Cap.fork; Cap.exec >` and Control none, as the spec says. Tabs does not receive none: it creates handles from system randomness, writes screenshots, `run --out` files and proposals, reads uploads and playbooks, and looks up the XDG directories, so `Tabs.caps = < Cap.env; Cap.fs_read; Cap.fs_write; Cap.random >`. Desktop (the handoff's focus and notify commands) receives `< Cap.fork; Cap.exec >`. Leash's gate runs with no allow-list.
- Semgrep 1.164.0 from nixpkgs is in the dev shells of ox and Leash.

## Story → test

| Story | Test |
| --- | --- |
| ^ncaps-sojd | `test/caps/caps_tests.ml` "ncaps-sojd rows compose and narrow" |
| ^ncaps-0mvw | `caps_tests.ml` "ncaps-0mvw the Door hands the powerbox" (program and a config command get `env.caps`); `compile_fail/forged.ml`; gate rule `ox-caps-mint` in `test/caps/gate` |
| ^ncaps-4btv | `caps_tests.ml` "wrappers are the raw calls" and "capabilities in local closures" (with `Rate_limiter.run` and `Resource.use_in_scope`) |
| ^ncaps-n6r0 | `test/caps/gate/check.sh`: every rule fires on `violating/`, `nosemgrep` is ignored, `test/` is outside, `clean/` passes |
| ^ncaps-w6n2 | the same, through the installed `caps-gate`, and `--allow` excludes exactly its file; `scripts/caps-gate` green in ox and Leash |
| ^ncaps-jkku ^ncaps-x7z8 | `caps_tests.ml` "spawn takes fork, exec and Eio's mgr"; the declarations in `Listener`, `Ox_otel`, `Connection`, `Schedule` interfaces and `docs/caps.md` |
| ^ncaps-4tjy | Leash's suites unchanged in what they assert, with `Ox_test.powerbox ()` where a signature now asks; Leash's `scripts/caps-gate` green with no allow-list |
| ^ncaps-21nk | counts in `docs/caps.md` and rows 50–53 of `docs/issues/README.md` |
| ^ncaps-vlwm | `compile_fail/portable.ml` (a capability cannot enter a `portable` closure) with `portable_control.ml`; `docs/caps.md` |
| ^ncaps-xzx5 | `docs/caps.md` |
| ^ncaps-2ydl | `AGENTS.md` of ox and Leash |
| ^ncaps-aw5n | `compile_fail/excluded.ml` refused ("has no method exec"), `included.ml` compiles |
| ^ncaps-iirv | `docs/adr/0007-named-third-party-dependencies.md` |

## Verification

Verified 2026-09-29 on 5.4.0+ox: in ox `dune build @install`, `dune test` (`test/caps`: 5 cases, 5 compile checks, 5 gate checks), `dune build @fmt` and `scripts/caps-gate` pass; Leash builds and passes `dune build @install`, `dune test`, `dune build @fmt` and its `scripts/caps-gate` against a private install of this tree (`dune install --prefix` + `OCAMLPATH`); live acceptance not run.
