---
status: completed
package: every package; the repository itself
consumer: Leash, Pie, nema, inn, grip, nixos-config
---

# ox: rename Eta, detach a fresh repository, publish privately

## Problem Statement

The name "Eta" named an effect type — `('a, 'err) Effect.t` — that no longer exists. Every document has to explain "Eta, but not the effect system"; the v1 tickets read as current to anyone who does not know the history; and the repository carries v1's 3080 commits, 138 MB of `.git`, 552 tracked research files (7 GB on disk) and 36 stale worktrees for a 4 MB tree of 103 commits that is the actual library. The operator's habit on a concept change is a new name, not a `v2`: Eta is dead to him, and the thing that replaced it is direct-style libraries over Eio for OxCaml whose floor is Scala Ox. ADR-0009 already says so.

## Solution

The library becomes **ox**: packages `ox`, `ox_http`, `ox_sql`, …; modules `Ox`, `Ox_http`, …; environment variables `OX_*`. It lives in a **fresh repository** at `~/projects/ribelo/ocaml/ox` whose history is the eta-next line (the 103 commits since `v1`) rewritten to drop `.scratch/`, pushed to the new private `github.com/ribelo/ox`. `github.com/ribelo/eta` and the local `Eta` checkout stay as the v1 archive, untouched, still pinned by taumel and p-doom. Every active consumer is renamed in the same pass and pointed at the new repository; Leash gets its first remote (`github.com/ribelo/leash`, private, already created). `ppx_yojson_minimal` keeps its name. Story IDs never change.

## User Stories

### The repository

1. As the operator, I want a new repository at `~/projects/ribelo/ocaml/ox` whose `master` is the eta-next line (`v1..master` of Eta) with every `.scratch/` path removed from history, so that ox starts with the 103 commits that are actually the library and no research bundles. ^oxname-7exn
2. As the operator, I want the rewritten history to keep every commit message, author, date and story-ID citation, so that `git log` and the delivery map still tell the true story. ^oxname-x65z
3. As the operator, I want a `v1-boundary` tag on ox's root commit naming the Eta commit it came from (`ad2ee1df`) and Eta's `v1` tag, so that the archive is one hop away. ^oxname-jig0
4. As the operator, I want ox's `origin` to be `github.com/ribelo/ox` (private, created 2026-09-29) and `master` pushed there, so that the library has an off-machine copy for the first time since eta-next began. ^oxname-m57z
5. As the operator, I want the Eta checkout and `github.com/ribelo/eta` left exactly as they are — no rename, no force-push, no deletion — with one final commit on Eta's master adding `ARCHIVED.md` that says the library continues as ox and where, so that v1 is an archive, not a corpse. ^oxname-vbjs
6. As the operator, I want Eta's 36 worktrees listed in `ARCHIVED.md` with their branches, and none of them removed by this row, so that the research trees are known and the decision to delete them is a separate one. ^oxname-8zob

### The name

7. As a maintainer, I want every package `eta*` renamed `ox*` (`eta` → `ox`, `eta_http` → `ox_http`, and so on for all 19), every library and public module `Eta*` → `Ox*`, every `dune`, `dune-project`, `*.opam`, flake output and `docs/packages` row updated, so that the name is consistent everywhere in the repository. ^oxname-vp1p
8. As a maintainer, I want `ppx_yojson_minimal` to keep its name, so that a deriver that may later be replaced by jsonkit does not carry the library's brand. ^oxname-0ga1
9. As a maintainer, I want the environment variables `ETA_PATH`, `ETA_REPO_ROOT`, `ETA_OPAM_PACKAGES`, `ETA_LADYBUG_LIBRARY` renamed `OX_*`, and the install helper `eta-opam-install-ox` renamed `ox-opam-install`, so that the shell surface matches. ^oxname-cobb
10. As a maintainer, I want `GLOSSARY.md`, `AGENTS.md`, `docs/why-next.md` (renamed `docs/why-ox.md`), the ADRs, `docs/modes.md`, `docs/migration-plan.md` and the delivery map to say ox, with *eta* added to the retired words and one paragraph in `why-ox.md` recording the rename and its reason, so that the documents match the code. ^oxname-z3ib
11. As a maintainer, I want story IDs, their prefixes and the `docs/issues` history left exactly as they are (`ncore-*`, `napp-*` stay), with new specs free to use ox-flavoured prefixes, so that tests and tickets keep citing stable names. ^oxname-gsrn
12. As a maintainer, I want the `v1:` references in specs and the map (`git show v1:lib/...`) to keep working by ox having Eta as a second remote named `eta` fetched read-only, so that "copy from v1" instructions still resolve inside the ox checkout. ^oxname-y149

### The consumers

13. As the operator, I want Leash, Pie, nema, inn and grip renamed in the same pass — module references, `dune`, `dune-project`, opam files, flake inputs (`github:ribelo/ox` or `git+file` to the new path, the operator's call per repo; default `git+file:///home/ribelo/projects/ribelo/ocaml/ox`), `ETA_*` → `OX_*` in their flakes and scripts — relocked, gates green, committed, so that no consumer is ever half-renamed. ^oxname-5q85
14. As the operator, I want the shared switch moved: `eta*` packages removed and `ox*` installed by the renamed helper, Pie's and nema's running binaries preserved as before and swapped only with the operator's word, so that production is not touched by a rename. ^oxname-bhcw
15. As the operator, I want nixos-config's `shell-stack.nix` and any other file naming `ETA_*` or the Eta path updated and committed, with the system evaluating (`nixosConfigurations.desktop`), so that the next rebuild is consistent. ^oxname-wt7z
16. As the operator, I want Leash to get `origin` = `github.com/ribelo/leash` (private, created 2026-09-29) and its `master` pushed, so that Leash also has an off-machine copy. ^oxname-t8uz
17. As the operator, I want the `leash` skill and any dotfiles skill mentioning Eta updated and committed, so that agents read the right name. ^oxname-ts1n

### Order and proof

18. As a maintainer, I want this row to start only after row 45 (supervised-error) is landed and Eta's tree is clean, and rows 46–48 to be written and implemented under the ox name in the ox repository, so that new modules are born with the right name. ^oxname-wqzj
19. As a maintainer, I want the whole pass to be one ordered sequence — repository, rename, consumers, switch, nixos-config, remotes — with a checklist in this spec's status ticked as each lands, and every repository clean at the end, so that a half-done rename cannot be left behind. ^oxname-j9l3
20. As the operator, I want the eta-next worktree, the `eta-next` branch and the `wip/eta-main-checkout-2026-09-26` branch left in Eta as they are (archive), and the Leash, Pie, nema, inn and grip `docs/` that mention `eta-next` updated to ox only where they describe the present, so that history stays history. ^oxname-51nx

## Implementation Decisions

- Fresh repository: `git clone --no-hardlinks` of Eta into `ox`, then `git filter-repo --path .scratch --invert-paths --refs master` (or `filter-branch` if `filter-repo` is unavailable in the switch's nix shell; install it via `nix shell nixpkgs#git-filter-repo`), then truncate history to `v1..` by grafting: `git replace --graft <ad2ee1df> ` with no parents followed by `filter-repo` to make it permanent. Verify: `git rev-list --count master` ≈ 103, `git ls-files | grep -c .scratch` = 0, tree at `master` byte-identical to Eta's `master` tree minus `.scratch/`.
- Rename mechanics: a script `scripts/rename-eta-to-ox.sh` committed in ox that applies the same `sed` rules to any tree (`\beta_([a-z0-9_]+)\b` → `ox_\1`, `\bEta_([A-Za-z0-9_]+)\b` → `Ox_\1`, `\bEta\b` → `Ox`, `\beta\b` in dune/opam/flake contexts → `ox`, `ETA_` → `OX_`), excluding `.git`, `_build`, `docs/issues/**` bodies' story IDs (IDs contain no `eta` token, but check), and `ppx_yojson_minimal`. Directory `lib/eta` → `lib/ox`. Run it on ox first, then on each consumer; gates prove each.
- Word-boundary care: `eta` appears inside `beta`, `theta`, `metadata`? — `\b` handles `beta`/`theta`; grep the diff for false hits before committing.
- Consumers' flake input default is the local path (they build from local checkouts today); the GitHub URL is documented as the alternative.
- The Eta archive commit is one file; nothing else changes in Eta after it.

## Testing Decisions

- The gates of every repository (build, test, fmt) after its rename are the test; plus `git ls-files | grep -c 'eta'` = 0 in ox outside `docs/issues` and `docs/adr`; plus `nix eval` of the desktop system in nixos-config; plus `gh repo view ribelo/ox` showing the pushed `master`.

## Out of Scope

Deleting Eta's worktrees or branches; changing story IDs; renaming `ppx_yojson_minimal`; making either GitHub repository public; pushing consumers other than Leash (Pie, nema, inn, grip already have remotes and are pushed only when the operator asks).

## Status

Ticked as the ordered pass lands (story ^oxname-j9l3); every repository is clean when the last box is ticked.

- [x] **Repository.** `~/projects/ribelo/ocaml/ox`: 104 commits, no `.scratch/` path in any commit's tree, tree byte-identical to Eta's `master` minus `.scratch/`, commit messages/authors/dates identical to Eta's `v1..master`; `v1-boundary` tag on the root commit (`7b60acf0`) naming Eta `ad2ee1df` and Eta's `v1` (`5b3affc8`).
- [x] **Remotes and push.** `origin` = `git@github.com:ribelo/ox.git`, `master` and `v1-boundary` pushed; `eta` = the Eta checkout, read-only (push URL disabled), fetching `refs/tags/v1` so `git show v1:…` keeps resolving.
- [x] **The rename in ox.** 19 opam packages `eta*` → `ox*`, modules `Eta*` → `Ox*`, `lib/eta` → `lib/ox`, `ETA_*` → `OX_*`, `eta-opam-install-ox` → `ox-opam-install`, `docs/why-next.md` → `docs/why-ox.md` with the rename paragraph; applied by `scripts/rename-eta-to-ox.sh` and reviewed for false hits; gates green.
- [x] **Consumers.** Leash `2345d05`, Pie `7cf7996`, nema `c40463b`, inn `c405450`, grip `a4973dd`: same script, flake input `git+file:///home/ribelo/projects/ribelo/ocaml/ox?ref=master`, only the `eta`→`ox` lock node relocked, story IDs untouched; gates green (Leash 23 suites/273 tests, Pie 36/566 with `EIO_BACKEND=posix`, nema 36/716, inn 2/52, grip 6/60; no `.ocamlformat` in nema, inn or grip). Only Leash was pushed, and only Leash's own copy is on GitHub. Hand fixes the rename needed: Pie's provenance filter compared three characters with "eta" (two with "ox") and named the real stub files; nema's two C mock fixtures matched 23 characters of a 22-character prefix; one `.gitignore` entry named an existing `.opam-eta-src/` directory.
- [x] **Shared switch.** `5.4.0+ox`: the 19 `eta*`/conf-eta-oxcaml packages plus `pie` and the old `ppx_yojson_minimal` removed, 20 `ox*` packages installed by `ox-opam-install` at `fa3ea69`; `oxcaml-*` guards untouched; `bin/pie` sha256 identical before and after (`4c8e28e2…`), as are `bin/grip` and `bin/inn`; nema still runs `/nix/store/x3b3jv6zy…-nema-dev`; no service stopped or restarted.
- [x] **nixos-config.** `bde763a`: `ox-opam-install`/`ox-oxcaml-test-shipped` and Ox prose in the OCaml setup script and the two requirement docs; no rebuild, `nix eval .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath` = `/nix/store/iqq9pv49…-nixos-system-heisenbug-26.11.20260826.9fbb54b.drv`.
- [x] **Remotes.** Leash's `origin` = `github.com/ribelo/leash`, `master` pushed; dotfiles `8732dcc4` (the OCaml skills that named the shared library; the `leash` skill itself has no rename-visible name and is unchanged).
- [x] **Eta archive.** One commit, `d169a91e`, adding `ARCHIVED.md` (the 36 worktrees with their branches, the two parked `wip` branches); no other change to Eta, nothing pushed, nothing deleted.

## Further Notes

Decision of 2026-09-29: bare `ox`, not `oxc` (oxc is the JavaScript toolchain the operator uses daily; the Scala Ox collision is intended — it names the floor). The GitHub repositories `ribelo/ox` and `ribelo/leash` were created private by the coordinator before this spec was written; `ribelo/eta` is public and stays the v1 archive.
