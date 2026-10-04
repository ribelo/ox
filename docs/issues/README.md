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
| 38 | `tls-close/01-tls-close.md` | `ox_http` | 19 | Pie (row 32) | [x] |
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
| 50 | `caps/01-caps.md` story 9 (^ncaps-21nk): Pie's caps row, its own spec in Pie | Pie; `ox_ipc` (`Listener.run` takes `fs_write` + `network`), `ox_otel` (`random`) | 48 | Pie's raw calls typed; 87 gate findings in 20 files today (Leash's were 40 in 6: 17 interface annotations, ~150 threading sites) | [x] |
| 51 | `caps/01-caps.md` story 9: nema's caps row | nema | 48 | 58 findings in 14 files today | [x] |
| 52 | `caps/01-caps.md` story 9: inn's caps row | inn; `ox_sql` (`time`, `fs_read`, `tmp`, `fs_write`), `ox_otel` | 48 | 54 findings in 5 files; inn spec `docs/issues/caps` | [x] |
| 53 | `caps/01-caps.md` story 9: grip's caps row | grip; `ox_otel` (`create ~caps` required), `Schedule.start` (no default seed), `Ox_app.with_powerbox` | 48, 50, 52 | grip's 39 findings in 8 files; `Ox_otel` and `Schedule` left the allow-list | [x] |
| 49 | `ox-rename/01-ox-rename.md` | everything | 45 | the library is ox in a fresh private repository; consumers and nixos-config follow; Leash gets a remote | [x] |
| 54 | `caps-gate-2/01-caps-gate-2.md` | `ox_caps`, gate | 48 | no silent skips; minting only at the Door; Leash live run after caps | [x] |
| 55 | `posix-wakeup/01-posix-wakeup.md` | `ox_app`, `ox` | 48 | bounded SIGCHLD wakeup on posix; Pie swap precondition; jitter compile-time again | [x] |
| 56 | `door-5/01-door-5.md` | `ox_app` | 43, 55 | Leash L41: JSON diagnostics, grouped help with real exits, bare orientation | [x] |
| 57 | [ws-full-duplex/01-ws-full-duplex.md](ws-full-duplex/01-ws-full-duplex.md) | `ox_http` | 22, 38 | Pie long recordings and concurrent WSS sessions | [ ] |
| 58 | `linear-defaults/01-linear-defaults.md` | `ppx_yojson_minimal` | 15, 17 | Pie: a wide defaulted config record derives in linear code | [x] |
| 59 | [pie-api-gaps/01-pie-api-gaps.md](pie-api-gaps/01-pie-api-gaps.md) | `ox_ai`, `ox_ai_openrouter`, `ox_http` | 25, 35, 40, 57 | Pie: audio/text Responses and precise transport deadlines | [x] |
| 60 | `stress/01-stress.md` | `ox`, `ox_http`, `ox_ipc` | 45, 57 | stress and fuzz under the seams where every ox bug has lived | [x] |
| 61 | [once-forks/01-once-forks.md](once-forks/01-once-forks.md) (P1) | `ox` | 45 | ownership: a value moved into one fiber or one release; ADR-0010 | [ ] |
| 62 | [owned-handles/01-owned-handles.md](owned-handles/01-owned-handles.md) (P2) | `ox_process`, `ox_http`, `ox_sql` | 61 | no use after close, wait or shutdown | [ ] |
| 63 | [duplex-halves/01-duplex-halves.md](duplex-halves/01-duplex-halves.md) (P3) | `ox_http` | 57, 61, 62 | the row-57 class refused by the compiler; buffer mutexes go | [ ] |
| 64 | [spawner/01-spawner.md](spawner/01-spawner.md) (P5) | `ox`, `ox_ipc`, `ox_http`, `ox_rpc`, `ox_app` | 61 | forking after `create` is declared in `deps` | [ ] |
| 65 | [ox-mutex/01-ox-mutex.md](ox-mutex/01-ox-mutex.md) (P7) | `ox` | 61 | branded guarded data; `Ox.Cancel.protect`; replacements for row 66 | [ ] |
| 66 | [raw-concurrency-gate/01-raw-concurrency-gate.md](raw-concurrency-gate/01-raw-concurrency-gate.md) (P6) | gate rules, `ox_sql`, `ox_sql_dsl`, `ox_http` | 54, 61, 64, 65 | no raw Eio concurrency or Stdlib mutex; catch-all, `Fun.protect`, discarded result, public exception, `Obj.magic*` rules | [ ] |
| 67 | [ws-typestate/01-ws-typestate.md](ws-typestate/01-ws-typestate.md) (P8) | `ox_http` | 62, 63 | close codes, reasons and phases typed | [ ] |
| 68 | [parse-dont-validate/01-parse-dont-validate.md](parse-dont-validate/01-parse-dont-validate.md) (P9) | `ox`, `ox_app`, `ox_http`, `ox_observability`, `ox_ai`, `ox_json`, `ox_blocking` | — | ADR-0008 applied to the kernel; one Door spec record | [ ] |
| 69 | [ppx-let/01-ppx-let.md](ppx-let/01-ppx-let.md) | `ppx_ox_let` (new), `ox` | 15 | `local`/`yielding` values usable after a bind; unblocks 70 and 71 | [ ] |
| 70 | [local-scope/01-local-scope.md](local-scope/01-local-scope.md) (P4) | `ox` | 61, 64, 69 | scope handles cannot escape (store, return, capture in a fork); built on row 69 | [ ] |
| 71 | [suspend-token/01-suspend-token.md](suspend-token/01-suspend-token.md) | `ox`, `ox_http`, `ox_ipc`, `ox_rpc`, `ox_blocking` | 65, 66, 69 | suspending inside a critical section is a compile error | [ ] |
| 72 | [read-only-status/01-read-only-status.md](read-only-status/01-read-only-status.md) | `ox_app`, `ox` | — | `status : t @ read`; decides `SERVICE` | [ ] |
| 73 | [cancellation-value/01-cancellation-value.md](cancellation-value/01-cancellation-value.md) | spike, docs | 71 | done: ADR-0011 rejects a recoverable token (second cancellation model) | [x] |
| 74 | `upstream-eio/01-upstream-eio.md` | flake, `dune-project`, `ox_test`; Leash, Pie, inn, nema, grip flakes | 60 | upstream Eio 1.6 everywhere; the `oxcaml/eio` snapshot is gone | [x] |
| 75 | [suspend-token-cost/01-suspend-token-cost.md](suspend-token-cost/01-suspend-token-cost.md) | spike, docs | 71 | measures the suspension token on ox, Leash and nema; done: migrate Leash and nema after fixing their violations; Logger must never park | [x] |
| 76 | [flow/01-flow.md](flow/01-flow.md) | `ox` (Flow) | 46, 61 | Scala Ox's streams built as `docs/design/flow.md` specifies | [ ] |
| 77 | [adaptive-retry/01-adaptive-retry.md](adaptive-retry/01-adaptive-retry.md) | `ox` (Retry) | 65 | retries share a token bucket | [ ] |
| 78 | [rate-limiter-duration/01-rate-limiter-duration.md](rate-limiter-duration/01-rate-limiter-duration.md) | `ox` (Rate_limiter) | 65 | limits by running operations, not starts | [ ] |
| 79 | [circuit-breaker/01-circuit-breaker.md](circuit-breaker/01-circuit-breaker.md) | `ox` (Circuit_breaker) | 65, 72 | Scala Ox's breaker with typed drops | [ ] |
| 80 | [compute-pool/01-compute-pool.md](compute-pool/01-compute-pool.md) | `ox` (Compute) | 61, 65 | CPU work on other domains; `portable` jobs | [ ] |
| 81 | [cron-schedule/01-cron-schedule.md](cron-schedule/01-cron-schedule.md) | `ox` (Schedule) | — | parsed cron expressions as schedules | [ ] |
| 82 | [kafka/01-kafka.md](kafka/01-kafka.md) | `ox_kafka` (new) | 76 | Kafka as Flow sources, sinks and commit stages; binding ADR first | [ ] |
| 83 | [ox-sync/01-ox-sync.md](ox-sync/01-ox-sync.md) | `ox` | 61, 62, 65 | Promise, Semaphore, Channel ends, Condition, Barrier, Latch at least as safe as `await`'s | [ ] |
| 84 | [typed-boundaries/01-typed-boundaries.md](typed-boundaries/01-typed-boundaries.md) | `ox`, `ox_http`, `ox_ipc`, `ox_rpc`, `ox_sql`, `ox_blocking` | 73, 83 | the part of `await` ADR-0011 adopted: an Ox-owned boundary returns a value, a foreign interruption stays an exception | [ ] |
| 85 | [simulation/01-simulation.md](simulation/01-simulation.md) | `ox_test`, `ox`, `ox_http`, `ox_ipc`, `ox_rpc` | 60 | seeded deterministic world; cancellation and fault sweeps; the five historical bug classes as cases | [ ] |
| 86 | [usage-rules/01-usage-rules.md](usage-rules/01-usage-rules.md) | docs, `scripts/ox-check`, gate | 66, 85 | one page per rule with its check, a machine-readable index, one command an agent runs; the 2026-10-04 research folded in | [ ] |
| 87 | [ox-lint/01-ox-lint.md](ox-lint/01-ox-lint.md) | `ox_lint` (new, build-time) | 66, 86 | our own rule decider on the pinned compiler's `compiler-libs`: Parsetree now, Typedtree from `.cmt` where types are needed; ast-grep has no OCaml, Semgrep's is Experimental | [ ] |
| — | taumel, p-doom | stay on `v1` | — | dormant since August; crux/signal/jsoo move to taumel if it wakes | — |

Rows 3 and 0 have no dependency on core and can start at once; 6, 7, 8 are independent of each other once 1 and 2 exist. Third wave: 15 then 16, before Leash L1's Config and protocol types are written (ADR-0008: types are the schema); row 14 (door-validate) is the agent's own and stays. Second wave: 9 and 10 first (Leash's dev loop and the shapes it needs), then 11, 12, 13 in parallel; 12 is last to land because it touches every signature, and 13's ported cases must pass after 12. Specs for HTTP, AI (OpenRouter), SQL and blocking are listed above. Row 27 records why the measured stream operations need no package; domain parallelism is the compute pool, row 80.

Running alongside, not blocking: the local-handler spike in `../../.scratch/research/handled-pattern/` decides whether ADR-0002's error channel is revisited. Rows do not wait for it; if it wins, the change is a new spec.

Rows 22–28 are delivered. Rows 29–32 are the consumer migrations in the order `../migration-plan.md` gives; each is a ticket in the *consumer's* repository (to-spec format, its own story prefix) that pins eta-next and ports the consumer whole — no bridge, no dual runtime. The consumer's ticket lists the kernel gaps it found; each gap becomes a new row here before the next consumer starts. Row 32 landed on 2026-09-28; `eta-next` became `master` on 2026-09-29 (`5b09ee47`), and `v1` stays a tag (`5b3affc8`) for taumel and p-doom. Packages leaving Eta for a consumer (Ladybug → nema, crux/signal/jsoo → taumel, linux_input → grip) are tickets in the receiving repository, not here.

Rows 61–73 implement ADR-0010 (modes type ownership and lifetime; Ox is the one trusted cast). P1–P9 are the proposals accepted on 2026-10-03; 69, 71, 72 and 73 came out of the same night's check of what OxCaml and Jane Street's `await`/`capsule` already solve. Order: 61, then 62–65 in parallel, then 66 (it needs their replacements), 67 after 63; 68 and 72 are independent; 69 unblocks 70 and 71. All of rows 61–73 are accepted (2026-10-04); 71's consumer migration waits for row 75's measurement.

Rows 76–82 are Scala Ox floor items this map once recorded as rejected "for want of a consumer"; ADR-0003 as amended reopens them (Ox is its own consumer). Row 83 replaces Eio's synchronization primitives where `await`'s or a `unique`-typed version refuses more at compile time.

The five research passes of 2026-10-04 (Eio community practice, OxCaml mode patterns, deterministic simulation, machine-checkable rules, the neighbouring ecosystems) are kept in [usage-rules/research/](usage-rules/research/) and were folded into rows 65, 66, 71, 84, 85, 86 and ADR-0010; what they rejected stays in their own section 3.

Row 87 is the decider rows 66 and 86 need: the proof that it is cheap is `docs/issues/suspend-token-cost/evidence/census.ml`, 57 lines of `compiler-libs` that walked all of ox.

Rows 84–86 answer what ADR-0011 left open. 84 builds the option it chose instead of a cancellation token. 85 moves the only mechanism that catches timing bugs — seeded deterministic simulation — from an opt-in alias to the default shape of a concurrency test. 86 exists because ox is written only by agents: a rule they cannot verify mechanically is not a rule, so every rule gets its check and one command runs them.

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
