---
status: ready-for-agent
package: flake.nix, dev shell
consumer: Leash (its `nix develop` shell); every future eta-next consumer
---

# The shared OxCaml switch carries eta-next, not v1

## Problem Statement

The `5.4.0+ox` opam switch at `/home/ribelo/.cache/opam/5.4.0+ox` holds v1's Eta packages, installed by the v1 flake's `eta-opam-install-ox`. Leash's dev shell (copied from Pie) installs "Eta's packages" into that same switch from `ETA_PATH`, now `../ocaml/eta-next`; eta-next's `eta` would collide with v1's `eta`. Decision (2026-09-26): the shared switch is replaced by eta-next. v1 consumers (Pie, inn, nema, taumel, grip, p-doom) are compiled and working and are not being developed; they are not rebuilt until they migrate. No second switch.

## Solution

eta-next's flake provides the same-named `eta-opam-install-ox` shell command that removes every v1 `eta*` package from the switch and pins/installs eta-next's packages from this checkout, idempotently; Leash's shell calls it unchanged.

## User Stories

1. As a Leash developer, I want `eta-opam-install-ox` from the eta-next dev shell to remove all installed `eta*` packages that are not declared in eta-next's `dune-project`, then pin and install eta-next's packages from this checkout, so that one command moves the switch to eta-next. ^nswitch-f18u
2. As a Leash developer, I want the command to be idempotent and fast when nothing changed (compare the pinned commit), so that opening a shell is not a rebuild. ^nswitch-a8ef
3. As an operator, I want the command to print which packages it removed and which commit it installed, so that a broken v1 build afterwards is explainable. ^nswitch-gr6k
4. As a Leash developer, I want `cd leash && nix develop -c dune build @install && nix develop -c dune test` to pass with the shared switch on eta-next, so that Leash's dev loop works. ^nswitch-qyr0

## Implementation Decisions

- Keep the v1 mechanism's name and environment variables (`ETA_REPO_ROOT`, `ETA_OPAM_PACKAGES`) so Leash's flake needs no change beyond what it already has.
- Removal is by name pattern `eta*` minus the declared set; never touch non-Eta packages; never touch the compiler.
- Pin kind `git` at `HEAD` of this checkout's branch.

## Testing Decisions

- Run it twice; assert the second run installs nothing. Then run Leash's gates (story 4). Record the switch's `opam list` before/after in this spec's status.

## Out of Scope

A second switch; rebuilding v1 consumers.
