# eta-next delivery map

Everything an implementing agent needs, in order. Each row is one spec under this directory; the spec says what must be true when it is done. Rows are delivered on the `eta-next` branch (this worktree), each as its own commits citing story IDs. Read `../../AGENTS.md`, `../../CONTEXT.md`, `../why-next.md` and the five ADRs first — they are short and they are the rules.

## Order

| # | Row | Package | Depends on | Unblocks | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | Build skeleton: make this empty tree build and test under `nix develop`. The flake was copied from v1 and its `ETA_OPAM_PACKAGES` list and `packages` outputs name v1 packages that no longer exist; make both derive from the packages actually declared in `dune-project` (start: `conf-eta-oxcaml` only), keep the OxCaml 5.4.0+ox switch check, keep `.ocamlformat`. Add `lib/` and `test/` directories with a placeholder test so `dune test` is green. | — | — | everything | [x] |
| 1 | `core/01-core.md` | `eta` | 0 | 2–8 | [x] |
| 2 | `test/01-test.md` | `eta_test` | 1 | all tests | [x] |
| 3 | `json-and-schema/01-json-and-schema.md` | `eta_json`, `eta_schema`, `eta_schema_yojson` | 0 | 4, 5, Leash protocol | [x] |
| 4 | `observability/01-observability.md` | `eta_observability` | 1, 3 | 5 | [x] |
| 5 | `app/01-app.md` | `eta_app` | 1, 3, 4 | Leash milestone 1 | [x] |
| 6 | `process/01-process.md` | `eta_process` | 1, 2 | Leash milestone 1 (Chrome) | [x] |
| 7 | `ipc/01-ipc.md` | `eta_ipc` | 1, 2 | Leash milestone 1 (control socket) | [x] |
| 8 | `rpc/01-rpc.md` | `eta_rpc` | 1, 2 | Leash milestone 1 (CDP) | [x] |
| 9 | `review-fixes-1/01-review-fixes-1.md` | `eta_app`, `eta`, root | 1, 5 | Leash pinning the branch | [x] |
| 10 | `shared-switch/01-shared-switch.md` | flake / dev shell | 0 | Leash's `nix develop` loop | [x] |
| 11 | `limits-1/01-limits-1.md` | `eta_test`, `eta_app`, `eta_process`, `eta_rpc`, `eta_ipc` docs | 1–8 | Leash milestone 1 tests | [x] |
| 12 | `modes-and-portability/01-modes-and-portability.md` | all | 1–9 | stable signatures before Leash pins | [x] |
| 13 | `port-v1-tests/01-port-v1-tests.md` | `test/` | 1, 4, 9 | trust in the combinators | [x] |
| 14 | `door-validate/01-door-validate.md` | `eta_app` | 5 | Leash L1 (svc-ljl3, svc-tkor) | [x] |
| 15 | `ppx-on-oxcaml/01-ppx-on-oxcaml.md` | toolchain | 10 | deriving anywhere | [x] |
| 16 | `remove-eta-schema/01-remove-eta-schema.md` | `eta_app`, `eta_observability`; removes `eta_schema*` | 15 | Leash L1 (Config, protocol types) | [x] |
| 17 | `ppx-yojson-minimal-2/01-ppx-yojson-minimal-2.md` | `ppx_yojson_minimal` | 15 | Leash drops its hand-written variant codecs; milestone 2 reply shapes | [x] |
| 18 | `fake-child-output/01-fake-child-output.md` | `eta_test` | 2 | Leash drops its scripted runner (etagap-43zf, hand-phof) | [x] |
| 19 | `http-client/01-http-client.md` | `eta_http` (client, h1, TLS) | 1, 2 | Leash milestone 5; every future HTTPS consumer | [x] |
| 20 | `ai-systemone/01-ai-systemone.md` | `eta_ai`, `eta_ai_systemone` | 19 | Leash drive (JEV) | [x] |
| 21 | `ai-chat/01-ai-chat.md` | `eta_ai_chat` | 20 | Leash drive (text helper) | [x] |
| 22 | (spec pending) `eta_http` WebSocket client | `eta_http` | 19 | Pie (Codex Realtime) | [ ] |
| 23 | (spec pending) `eta_http` server, routing, service helpers | `eta_http` | 19 | inn, nema | [ ] |
| 24 | (spec pending) `eta_sql` sqlite, DSL, pool, migrate | `eta_sql` | 1 | inn | [ ] |
| 25 | (spec pending) `eta_ai` Responses, embeddings, audio; Codex Realtime | `eta_ai` | 21, 22 | Pie, nema | [ ] |
| 26 | (spec pending) `eta_otel` exporter | `eta_otel` | 19 | nema | [ ] |
| 27 | (spec pending) `eta_stream` | `eta_stream` | 1 | Pie | [ ] |
| 28 | (spec pending) `eta_blocking` | `eta_blocking` | 1 | nema, grip | [ ] |

Rows 3 and 0 have no dependency on core and can start at once; 6, 7, 8 are independent of each other once 1 and 2 exist. Third wave: 15 then 16, before Leash L1's Config and protocol types are written (ADR-0008: types are the schema); row 14 (door-validate) is the agent's own and stays. Second wave: 9 and 10 first (Leash's dev loop and the shapes it needs), then 11, 12, 13 in parallel; 12 is last to land because it touches every signature, and 13's ported cases must pass after 12. HTTP, AI (OpenRouter), SQL, par/blocking and stream have no spec yet: they are written when Leash milestone 5 or another consumer pulls them (ADR-0003).

Running alongside, not blocking: the local-handler spike in `../../.scratch/research/handled-pattern/` decides whether ADR-0002's error channel is revisited. Rows do not wait for it; if it wins, the change is a new spec.

Rows 22–28 are the migration plan's order (`../migration-plan.md`); each gets a spec when its consumer's migration is scheduled, written from that consumer's actual usage. Packages leaving Eta for a consumer (Ladybug → nema, crux/signal/jsoo → taumel, linux_input → grip) are tickets in the receiving repository, not here.

## Definition of done, every row

- Every user story has a test citing its ID by name; `nix develop -c dune build @install`, `nix develop -c dune test` and `nix develop -c dune build @fmt` are green.
- A new package has a `dune-project` stanza (opam file generated), a `lib/<name>/` library with a `.mli` per module and doc comments stating cancellation and finalizer behaviour, tests under `test/<name>/`, and a line in `README.md`'s package list.
- Dependencies follow ADR-0005; the spec's `package:` frontmatter is the dependency ceiling.
- Copied v1 code is copied with `git show v1:<path>` and its tests, and every `Effect.t` reference is gone.
- Commit messages cite the story IDs delivered. Nothing else changes in the same commit.
- The spec's `status:` becomes `completed` with a two-line note of what was verified.

## Where to look in v1

`git show v1:<path>` from this worktree. Useful paths: `lib/eta/duration.ml`, `lib/eta/schedule.ml`, `lib/eta/cause.mli` (shape reference only), `lib/eta/effect.mli.in` lines 745–762 (`with_background` contract), `lib/json/`, `lib/schema/`, `lib/schema_yojson/`, `docs/issues/process-scoped-child/`, `docs/issues/ipc-control-listener/`, `docs/issues/stream-rpc-correlator/` (v1 findings that fed these specs), and Pie's `packages/pie/assistant_service/server.ml` for the socket-ownership sequence.

## The first consumer

Leash: `/home/ribelo/projects/ribelo/leash`. Its milestone 1 spec (`docs/issues/managed-chrome/`) names the stories each row above serves. When rows 1–8 are done, Leash pins `git+file:///home/ribelo/projects/ribelo/ocaml/Eta?ref=eta-next` in its flake and milestone 1 starts.
