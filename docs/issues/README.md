# eta-next delivery map

Everything an implementing agent needs, in order. Each row is one spec under this directory; the spec says what must be true when it is done. Rows are delivered on the `eta-next` branch (this worktree), each as its own commits citing story IDs. Read `../../AGENTS.md`, `../../CONTEXT.md`, `../why-next.md` and the five ADRs first — they are short and they are the rules.

## Order

| # | Row | Package | Depends on | Unblocks | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | Build skeleton: make this empty tree build and test under `nix develop`. The flake was copied from v1 and its `ETA_OPAM_PACKAGES` list and `packages` outputs name v1 packages that no longer exist; make both derive from the packages actually declared in `dune-project` (start: `conf-eta-oxcaml` only), keep the OxCaml 5.4.0+ox switch check, keep `.ocamlformat`. Add `lib/` and `test/` directories with a placeholder test so `dune test` is green. | — | — | everything | [ ] |
| 1 | `core/01-core.md` | `eta` | 0 | 2–8 | [ ] |
| 2 | `test/01-test.md` | `eta_test` | 1 | all tests | [ ] |
| 3 | `json-and-schema/01-json-and-schema.md` | `eta_json`, `eta_schema`, `eta_schema_yojson` | 0 | 4, 5, Leash protocol | [ ] |
| 4 | `observability/01-observability.md` | `eta_observability` | 1, 3 | 5 | [ ] |
| 5 | `app/01-app.md` | `eta_app` | 1, 3, 4 | Leash milestone 1 | [ ] |
| 6 | `process/01-process.md` | `eta_process` | 1, 2 | Leash milestone 1 (Chrome) | [ ] |
| 7 | `ipc/01-ipc.md` | `eta_ipc` | 1, 2 | Leash milestone 1 (control socket) | [ ] |
| 8 | `rpc/01-rpc.md` | `eta_rpc` | 1, 2 | Leash milestone 1 (CDP) | [ ] |

Rows 3 and 0 have no dependency on core and can start at once; 6, 7, 8 are independent of each other once 1 and 2 exist. HTTP, AI (OpenRouter), SQL, par/blocking and stream have no spec yet: they are written when Leash milestone 5 or another consumer pulls them (ADR-0003).

Running alongside, not blocking: the local-handler spike in `../../.scratch/research/handled-pattern/` decides whether ADR-0002's error channel is revisited. Rows do not wait for it; if it wins, the change is a new spec.

## Definition of done, every row

- Every user story has a test citing its ID by name; `nix develop -c dune build @install` and `nix develop -c dune test` are green.
- A new package has a `dune-project` stanza (opam file generated), a `lib/<name>/` library with a `.mli` per module and doc comments stating cancellation and finalizer behaviour, tests under `test/<name>/`, and a line in `README.md`'s package list.
- Dependencies follow ADR-0005; the spec's `package:` frontmatter is the dependency ceiling.
- Copied v1 code is copied with `git show v1:<path>` and its tests, and every `Effect.t` reference is gone.
- Commit messages cite the story IDs delivered. Nothing else changes in the same commit.
- The spec's `status:` becomes `completed` with a two-line note of what was verified.

## Where to look in v1

`git show v1:<path>` from this worktree. Useful paths: `lib/eta/duration.ml`, `lib/eta/schedule.ml`, `lib/eta/cause.mli` (shape reference only), `lib/eta/effect.mli.in` lines 745–762 (`with_background` contract), `lib/json/`, `lib/schema/`, `lib/schema_yojson/`, `docs/issues/process-scoped-child/`, `docs/issues/ipc-control-listener/`, `docs/issues/stream-rpc-correlator/` (v1 findings that fed these specs), and Pie's `packages/pie/assistant_service/server.ml` for the socket-ownership sequence.

## The first consumer

Leash: `/home/ribelo/projects/ribelo/leash`. Its milestone 1 spec (`docs/issues/managed-chrome/`) names the stories each row above serves. When rows 1–8 are done, Leash pins `git+file:///home/ribelo/projects/ribelo/ocaml/Eta?ref=eta-next` in its flake and milestone 1 starts.
