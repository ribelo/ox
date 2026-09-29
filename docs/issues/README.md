# Delivery map

> **Migration complete, 2026-09-29.** `master` was reset to `5b09ee47f92a3bc7ea5ee18b8e37c03f38b9594d` (the `eta-next` tip) and this record is the docs commit on top of it; the old master is the `v1` tag (`5b3affc840010c1ffa3420ad30df21a46f08bd87`). Leash, grip, inn, nema and Pie take their Eta input from `?ref=master` and are re-locked to it; taumel and p-doom stay on `v1` by pinned revision. See `../migration-plan.md`.

Everything an implementing agent needs, in order. Each row is one spec under this directory; the spec says what must be true when it is done. Rows were delivered on the `eta-next` branch, which became `master` on 2026-09-29; each row is its own commits citing story IDs. Read `../../AGENTS.md`, `../../CONTEXT.md`, `../why-ox.md` and the five ADRs first — they are short and they are the rules.

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
| 22 | `ws-client/01-ws-client.md` | `eta_http` | 19 | Pie (Codex Realtime) | [x] |
| 23 | `http-server/01-http-server.md` server, routing, service helpers | `eta_http` | 19 | inn, nema | [x] |
| 24 | `sql/01-sql.md` | `eta_sql`, `eta_sql_dsl` | 1 | inn | [x] |
| 25 | `ai-responses/01-ai-responses.md` Responses, embeddings, audio; Codex Realtime | `eta_ai_openrouter`, `eta_ai_realtime` | 21, 22 | Pie, nema | [x] |
| 26 | `otel/01-otel.md` exporter | `eta_otel` | 19 | nema | [x] |
| 27 | [stream/01-stream.md](stream/01-stream.md): measured; Eio/Seq suffice | — (no `eta_stream` package) | 1 | Pie | [x] |
| 28 | `blocking/01-blocking.md` | `eta_blocking` | 1 | nema, grip | [x] |
| 29 | **grip migrates to eta-next** (ticket in grip: `docs/issues/eta-next-migration/`). Move `eta_linux_input` into grip first (v1 ticket `remove-linux-input`), then port grip's ~10 Eta call sites (`Eta_eio` door → `Eta_app.run`, `Eta_blocking` → `eta_blocking`, one HTTP client call), pin eta-next, gates green, grip runs. Kernel gaps found become rows here. | grip | 19, 28 | proves the migration process on a 5k-line app | [x] |
| 30 | **inn migrates to eta-next** (ticket in inn). HTTP client + server + service helpers, SQL DSL/pool/migrate; port from `Effect.t` to direct style module by module; pin; gates; inn runs. First server + SQL consumer: expect gaps in rows 23–24 and file them here. | inn | 23, 24, 29 | second consumer of http server and sql | [x] |
| 31 | **nema migrates** (ticket in nema). Move `eta_ladybug` into nema first (copy from `v1:drivers/eta_ladybug`, keep on v1's Effect.t or rewrite direct-style, nema's call), then HTTP client + server, embeddings, OTel, blocking. | nema | 23, 25, 26, 28, 30 | largest active consumer | [x] |
| 32 | **Pie migrates** (ticket in Pie). WebSocket client + Codex Realtime, Responses/audio, the audio pipeline on Seq/Eio per row 27's probes, `Eta_app` door, control socket via `eta_ipc` (replacing Pie's own server). | Pie | 22, 25, 27, 31 | most specialised consumer, last active | [x] |
| 33 | `door-telemetry/01-door-telemetry.md` | `eta_app`, `eta_observability`, `eta_otel` | 14, 26 | Leash L25 OTLP by config | [x] |
| 34 | `otel-metrics/01-otel-metrics.md` | `eta_otel` | 26 | inn's instrumentation guide (row 30), nema | [x] |
| 35 | `openrouter-2/01-openrouter-2.md` | `eta_ai_openrouter` | 25 | Pie (row 32) | [x] |
| 36 | `door-2/01-door-2.md` | `eta_app` | 14, 33 | Pie (row 32) | [x] |
| 37 | `ipc-peer-reply/01-ipc-peer-reply.md` | `eta_ipc` | 7 | Pie (row 32) | [x] |
| 38 | `tls-close/01-tls-close.md` | `eta_http` | 19 | Pie (row 32) | [ ] |
| 39 | `blocking-settled/01-blocking-settled.md` | `eta_blocking` | 28 | nema (row 31) | [x] |
| 40 | `ai-transport-controls/01-ai-transport-controls.md` | `eta_ai`, `eta_ai_openrouter` | 20, 25 | nema (row 31) | [x] |
| 41 | `door-telemetry-result/01-door-telemetry-result.md` | `eta_app` | 33 | nema (row 31) | [x] |
| 42 | `door-3/01-door-3.md` | `eta_app` | 36 | nema (row 31) U4 | [x] |
| 43 | `door-4/01-door-4.md` | `eta_app` | 42 | nema (row 31) U4 | [x] |
| 44 | `otel-error-signal/01-otel-error-signal.md` | `eta_otel` | 26 | nema (row 31) | [x] |
| 45 | `supervised-error/01-supervised-error.md` | `eta` | 1 | typed errors across forks; Concurrent over Eio; consumers move | [x] |
| 46 | `ox-floor/01-ox-floor.md` | `ox`, `ox_app`, docs | 45 | rate limiter, select, resources, OxApp parity, Flow design | [x] |
| 47 | `actor/01-actor.md` | `ox`, Leash | 45 | typed mailbox with state fold, Supervisor, Agent; Leash registry, Chrome supervision and ledger move | [x] |
| 48 | `caps/01-caps.md` | `ox_caps`, `ox_app`, `ox_process`, Leash | 45 | capabilities in signatures; Semgrep gate; Leash first | [x] |
| 50 | `caps/01-caps.md` story 9 (^ncaps-21nk): Pie's caps row, its own spec in Pie | Pie; `ox_ipc` (`Listener.run` takes `fs_write` + `network`), `ox_otel` (`random`) | 48 | Pie's raw calls typed; 87 gate findings in 20 files today (Leash's were 40 in 6: 17 interface annotations, ~150 threading sites) | [ ] |
| 51 | `caps/01-caps.md` story 9: nema's caps row | nema | 48 | 58 findings in 14 files today | [ ] |
| 52 | `caps/01-caps.md` story 9: inn's caps row | inn; `ox_sql` (`time`, `fs_read`, `tmp`, `fs_write`), `ox_otel` | 48 | 52 findings in 5 files today | [ ] |
| 53 | `caps/01-caps.md` story 9: grip's caps row | grip; `ox_otel` | 48, 50, 52 | 39 findings in 8 files today; last user of `ox_otel` without `random`, so `Ox_otel` and `Schedule`'s default leave ox's allow-list here | [ ] |
| 49 | `ox-rename/01-ox-rename.md` | everything | 45 | the library is ox in a fresh private repository; consumers and nixos-config follow; Leash gets a remote | [x] |
| — | taumel, p-doom | stay on `v1` | — | dormant since August; crux/signal/jsoo move to taumel if it wakes | — |

Rows 3 and 0 have no dependency on core and can start at once; 6, 7, 8 are independent of each other once 1 and 2 exist. Third wave: 15 then 16, before Leash L1's Config and protocol types are written (ADR-0008: types are the schema); row 14 (door-validate) is the agent's own and stays. Second wave: 9 and 10 first (Leash's dev loop and the shapes it needs), then 11, 12, 13 in parallel; 12 is last to land because it touches every signature, and 13's ported cases must pass after 12. Specs for HTTP, AI (OpenRouter), SQL and blocking are listed above. Row 27 records why the measured stream operations need no package; domain parallelism stays deferred until a consumer pulls it (ADR-0003).

Running alongside, not blocking: the local-handler spike in `../../.scratch/research/handled-pattern/` decides whether ADR-0002's error channel is revisited. Rows do not wait for it; if it wins, the change is a new spec.

Rows 22–28 are delivered. Rows 29–32 are the consumer migrations in the order `../migration-plan.md` gives; each is a ticket in the *consumer's* repository (to-spec format, its own story prefix) that pins eta-next and ports the consumer whole — no bridge, no dual runtime. The consumer's ticket lists the kernel gaps it found; each gap becomes a new row here before the next consumer starts. Row 32 landed on 2026-09-28; `eta-next` became `master` on 2026-09-29 (`5b09ee47`), and `v1` stays a tag (`5b3affc8`) for taumel and p-doom. Packages leaving Eta for a consumer (Ladybug → nema, crux/signal/jsoo → taumel, linux_input → grip) are tickets in the receiving repository, not here.

Rows 45–48 implement ADR-0009 (Ox is the floor). Order: 45 first (it changes `Concurrent` that the others build on), then **49 (the ox rename) before anything else**, so that 46–48 are written and built under the ox name in the ox repository. Consumers (Pie, nema, Leash) are updated in the same rows where a story says so; they are internal tools and may change.

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

Leash: `/home/ribelo/projects/ribelo/leash`. Its milestone 1 spec (`docs/issues/managed-chrome/`) names the stories each row above serves. When rows 1–8 are done, Leash pins `git+file:///home/ribelo/projects/ribelo/ocaml/Eta?ref=master` in its flake and milestone 1 starts.
