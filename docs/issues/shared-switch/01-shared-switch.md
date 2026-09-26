---
status: completed
package: flake.nix, dev shell
consumer: Leash (its `nix develop` shell); every future eta-next consumer
---

# The shared OxCaml switch carries eta-next, not v1

## Problem Statement

The `5.4.0+ox` opam switch at `/home/ribelo/.cache/opam/5.4.0+ox` holds v1's Eta packages, installed by the v1 flake's `eta-opam-install-ox`. Leash's dev shell (copied from Pie) installs "Eta's packages" into that same switch from `ETA_PATH`, now `../ocaml/eta-next`; eta-next's `eta` would collide with v1's `eta`. Decision (2026-09-26): the shared switch is replaced by eta-next. v1 consumers (Pie, inn, nema, taumel, grip, p-doom) are compiled and working and are not being developed; they are not rebuilt until they migrate. No second switch.

## Solution

eta-next's flake provides the same-named `eta-opam-install-ox` shell command that removes every v1 `eta*` package from the switch and pins/installs eta-next's packages from this checkout, idempotently; Leash's shell calls it unchanged. A removed package takes the files of its installed dependents with it, so before the removal the command copies what those dependents need at run time and puts it back afterwards (story 5).

## User Stories

1. As a Leash developer, I want `eta-opam-install-ox` from the eta-next dev shell to remove all installed `eta*` packages that are not declared in eta-next's `dune-project`, then pin and install eta-next's packages from this checkout, so that one command moves the switch to eta-next. ^nswitch-f18u
2. As a Leash developer, I want the command to be idempotent and fast when nothing changed (compare the pinned commit), so that opening a shell is not a rebuild. ^nswitch-a8ef
3. As an operator, I want the command to print which packages it removed and which commit it installed, so that a broken v1 build afterwards is explainable. ^nswitch-gr6k
4. As a Leash developer, I want `cd leash && nix develop -c dune build @install && nix develop -c dune test` to pass with the shared switch on eta-next, so that Leash's dev loop works. ^nswitch-qyr0
5. As an operator, I want the already-compiled binaries of v1 consumers that live on the shared switch (`pie`, `grip`) to keep working after the move, so that switching the switch does not take a running service down or force a rebuild. ^nswitch-v1bn

## Implementation Decisions

- Keep the v1 mechanism's name and environment variables (`ETA_REPO_ROOT`, `ETA_OPAM_PACKAGES`) so Leash's flake needs no change beyond what it already has.
- Removal is by name pattern `eta*` minus the declared set; never touch non-Eta packages; never touch the compiler.
- Pin kind `git` at `HEAD` of this checkout's branch.
- Before removing, the command takes the installed non-Eta dependents of the removal set (`opam list --recursive --depends-on`), copies every `bin/`, `sbin/`, `share/`, `etc/` and `lib/stublibs/` file their `.opam-switch/install/<pkg>.changes` records into `<switch>/.opam-switch/preserved-by-eta-opam-install/<pkg>/`, and after the removal restores them as plain untracked files, printing each path. A file already at the destination is never overwritten; a dependent with no manifest is reported, not guessed at.

## Testing Decisions

- Run it twice; assert the second run installs nothing. Then run Leash's gates (story 4). Record the switch's `opam list` before/after in this spec's status.
- Preservation (story 5) is verified without touching the real services: a throwaway `--empty` switch beside the shared one with four fake packages — `eta` (declared, pinned at the same version as the pinned commit), `eta_http` (removed), and `pie`/`grip` (its dependents, installing `bin/` executables plus a shared `bin/pie`) — then the built `eta-opam-install` is pointed at it with `OPAMROOT`, `ETA_OPAM_SWITCH`, `ETA_REPO_ROOT` and `ETA_OPAM_PACKAGES=eta`.

## Out of Scope

A second switch; rebuilding v1 consumers.

## Further Notes

- Removal covers `ppx_eta*` as well as `eta*`: v1's preprocessors come from the same repository (their pins named `git+file:///home/ribelo/projects/ribelo/ocaml/Eta#master`), nothing in this tree's `dune-project` declares them, and an `eta*` pattern alone would have left them pinned and installable.
- The dev shell's entry prints the command's name and installs nothing itself, so `nix develop -c <gate>` never touches the shared switch. `ETA_OPAM_REF` is gone: the pin is at this checkout's `HEAD` per Implementation Decisions.
- `.changes` is opam syntax, so the preservation step reads every quoted path except the ones under `removed:`: opam writes a single-file install inline (`added: "bin/pie"`) and records a path another package overwrote as `contents-changed:`, and both are files the dependent still needs. Paths in the file are relative to the switch prefix; directories (`{"D"}`) are skipped because restoring a file recreates its parent.

Verification: `nix develop -c eta-opam-install-ox` moved `/home/ribelo/.cache/opam/5.4.0+ox` from v1 to eta-next: it removed 34 of the 36 installed eta-related packages (all `dev`, pinned to `git+file:///home/ribelo/projects/ribelo/ocaml/Eta#master`), dropped v1's stale `eta*`/`ppx_eta*` pins, pinned the 11 declared packages kind `git` at `c19c71a1d16c69cfd02d7afaf8128ad33dbb922d` and installed them; the compiler is untouched (`ocaml 5.4.0`, `ocaml-variants 5.4.0+ox`). Switch `opam list`, before: 184 installed, 36 eta-related — eta, eta_ai, eta_ai_anthropic, eta_ai_kimi_coding, eta_ai_moonshot, eta_ai_openai_codec, eta_ai_openai_codex, eta_ai_openai_compat, eta_ai_openrouter, eta_blocking, eta_component, eta_crux, eta_crux_json, eta_eio, eta_exa, eta_http, eta_http_eio, eta_http_h1, eta_http_h2, eta_http_service, eta_http_service_eio, eta_http_tls_openssl, eta_http_ws, eta_ladybug, eta_linux_input, eta_observability, eta_otel, eta_otel_eio, eta_par, eta_redacted, eta_router, eta_signal, eta_signal_map, eta_sql_driver, eta_sql_dsl, eta_stream. After: 157 installed, 11 eta-related, all at `c19c71a1` from `git+file:///home/ribelo/projects/ribelo/ocaml/eta-next#c19c71a1` — conf-eta-oxcaml, eta, eta_app, eta_ipc, eta_json, eta_observability, eta_process, eta_rpc, eta_schema, eta_schema_yojson, eta_test. `grip` and `pie` were installed on v1 `eta*` and opam removed them as reverse dependencies; that first run predates story ^nswitch-v1bn, the coordinator restored their binaries by hand, and the command now preserves files like theirs across the removal (third line).
Verification: a second run prints `nothing to do` and installs nothing in 1.7s; the same holds for Leash's unchanged call (`ETA_REPO_ROOT=…/eta-next`, `ETA_OPAM_PACKAGES` its nine packages, `nix develop …/eta-next -c eta-opam-install-ox`), and a later run converged the switch to the new `HEAD` in 16s. `cd leash && nix develop -c dune build @install && nix develop -c dune test` pass against the eta-next switch (Leash rebuilt after `dune clean`); eta-next's gates pass for the full tree: `nix develop -c dune build @install`, `nix develop -c dune test` (10 suites, 179 tests) and `nix develop -c dune build @fmt`, all three green from scratch on this tree before the row-11 worker's uncommitted edits appeared; with those in the working tree, `build @install` and `dune test` stay green and `@fmt` reports only their files.
Verification: ^nswitch-v1bn — a throwaway `--empty` switch holding fake `eta` (declared, kept), `eta_http` (removed) and its dependents `pie`/`grip` (each installing a `bin/` executable, `pie` also a shared `bin/pie` and `share/pie-data.txt`): the built command removed `eta_http`, `pie` and `grip`, kept `eta`, and put back `bin/grip`, `bin/pie` and `share/pie-data.txt` byte for byte — a local modification appended to `bin/pie` came back intact — printing `Kept existing …/bin/pie (not overwritten)` once; a second run removed nothing and rewrote nothing. On the real switch a rerun finds no undeclared `eta*` package and no installed dependent of the eta-next packages, creates no preservation directory, and leaves `bin/pie` (`sha256 9ba8bf92…`) and `bin/grip` (`sha256 39641ff9…`) untouched, converging the 11 packages to `42e41684755e8cba80ad36d5eae367b18db560ae`.

