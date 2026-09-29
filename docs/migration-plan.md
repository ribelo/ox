# Migration plan: v1 → eta-next, and the boundary of the kernel

Written 2026-09-27 from measurement, not memory: every consumer's actual `Eta_*` module references (not its opam declarations), and every v1 package's size and count of `Effect.t` references. Numbers are in the appendix.

## The two rules

1. **Eta provides what two or more of its consumers need, or what one needs and is general.** A database driver for one graph store, an input-device binding for one tool, a reactive-UI kernel for one app: those belong to the consumer. The consumer copies the v1 code into its own tree and owns it.
2. **Pure code is copied; effectful code is rewritten in direct style; nothing moves before a consumer's spec pulls it.** The measurement below says which is which.

## What the consumers actually use

| Consumer | Own LOC | Kernel | HTTP | SQL | AI | Other Eta | Last commit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Leash | ~5k | app, process, ipc, rpc, json, observability, test | (m5: client) | — | (m5: System One, chat) | — | active |
| Pie | 35k | core, eio, stream, stream_eio | client, **TLS**, **WebSocket client** | — | Responses, Wav, User, Text (OpenRouter + Codex Realtime) | observability | active |
| inn | 14k | core, eio | client, **server**, **http_service** | **sqlite, DSL (Select/Insert/Update/Delete/Expr), Pool, Migrate** | — | — | active |
| nema | 66k | core, eio, blocking | client, **server** | — | Embedding (OpenRouter) | **Eta_ladybug** (32 refs), otel, otel_eio | active |
| grip | 5k | core, eio, blocking | client (1 ref) | — | — | eta_linux_input (moving to grip) | active |
| taumel | 62k | core | client | — | — | **Eta_crux** (114 refs), signal_map, jsoo | 2026-08-25 |
| p-doom | 11k | core | client, Retry_policy | — | — | schema, cache | 2026-08-09 |

Nobody uses HTTP/2 from application code (Pie's 704 references are its vendored test suite, not its service). Nobody uses `eta_par`, `eta_router` directly, `eta_cache` beyond one reference, `eta_exa`, `eta_utop`, `eta_http_js`, `eta_js*`.

## What moves to a consumer (leaves Eta)

| Package | Goes to | Why | Size |
| --- | --- | --- | --- |
| `eta_ladybug` (in `drivers/`) | **nema** | one consumer, one graph database; a driver is nema's domain | driver tree in `drivers/eta_ladybug` |
| `eta_linux_input` | **grip** | already decided (v1 ticket `remove-linux-input`) | 575 |
| `eta_crux`, `eta_crux_json`, `eta_crux_sexp`, `eta_crux_test` | **taumel** | one consumer; a Bonsai-shaped state-machine kernel is an application framework, not a service kernel | 11.7k (426 effect refs: taumel rewrites or freezes it on its own terms) |
| `eta_signal`, `eta_signal_map`, `eta_signal_stream` | **taumel** | same; only crux and taumel use them | 8k, nearly pure |
| `eta_jsoo`, `eta_js`, `eta_js_test`, `eta_http_js` | **taumel** if it needs the browser side, else dropped | zero service consumers; the jsoo runtime was the interpreter's second backend | 2.1k |
| `eta_duckdb`, `eta_turso` (drivers) | **dropped** unless Pie's references turn out to be more than its vendored tests | no application code uses them | — |
| `eta_exa`, `eta_utop`, `eta_cache`, `eta_router` (as a package) | **dropped** | no consumer, or absorbed (`router` becomes part of `eta_http`'s server if inn's routes need it) | small |

Each move is one ticket in the *receiving* repository: copy from `v1:<path>`, keep tests, drop `Effect.t` if the consumer is on eta-next, or keep as-is if the consumer stays on v1 until it migrates.

## What eta-next provides, in delivery order

Order is by who is waiting, then by dependency. Rows 19–21 already exist on the map.

| Row | Package | Consumer waiting | Source | Notes |
| --- | --- | --- | --- | --- |
| 19 | `eta_http` client, h1, TLS | Leash m5 | h1 codec + OpenSSL binding **copied** (pure, 0 effect refs); transport rewritten | spec exists |
| 20–21 | `eta_ai` core, System One, chat | Leash m5 | rewritten (small) | specs exist |
| 22 | `eta_http` **WebSocket client** | Pie (Codex Realtime) | ws frame codec **copied** (206 lines, pure); `ws_client` rewritten over the new transport | the one Pie-only HTTP need; also the WebSocket establishment-timeout gap Pie recorded |
| 23 | `eta_http` **server** (h1) + routing + service helpers | inn, nema | h1 server connection rewritten (1.5k, 46 effect refs); `server.ml` is already effect-free; `eta_router` path matching **copied** (pure); `http_service` extractors rewritten (700 lines) | one package; no separate `eta_http_service` |
| 24 | `eta_sql` sqlite + DSL + pool + migrate | inn | `sql_dsl` and `ppx_sql` **copied** (3.6k, pure); sqlite binding (C stubs) **copied**; connection/pool/migrate rewritten (~1.2k, 90 effect refs) | `Eta_sql.Pool` becomes an `Eio.Pool` or a small pool over Eio; `Eta_sql.Eta_schema` (DSL schema) is unrelated to the removed schema DSL and stays |
| 25 | `eta_ai` **Responses** + embeddings + audio (OpenRouter), Codex Realtime session | Pie, nema | rewritten against the chat client's core; Codex Realtime rides on row 22 | Pie's STT and nema's embeddings; the other nine providers are not pulled |
| 26 | `eta_otel` exporter | nema | OTLP JSON encoding **copied** (pure, `otlp_json.ml`); exporter loop rewritten over `eta_http` client | logs+traces only; metrics when someone needs them |
| 27 [x] | No `eta_stream` package | Pie: 17 production operation references, 60 owned-test references (25 Eio adapters); no Mailbox use | `Seq`, direct result loops, `Eio.Stream` and consumer-owned admission state with Eio synchronization cover every measured operation | [Completed measurement and migration recipes](issues/stream/01-stream.md); six executable probes, no effect or compatibility library |
| 28 | `eta_blocking` / `eta_par` | nema, grip (blocking); nobody (par) | `blocking` as a thin wrapper over `Eio_unix.run_in_systhread` with a bounded pool; `par` deferred until a consumer needs domains | the heartbeat scheduler stays on v1 until pulled |
| — | HTTP/2 | nobody | deferred; codec is pure (4.6k) and copies when a consumer needs h2 | Pie's 704 refs are the vendored testsuite |

## Consumer migration order

Migrate a consumer only when eta-next has everything it uses; migrate whole, no bridge (ADR on v1). Order by readiness and value:

1. **Leash** — is on eta-next; m5 pulls rows 19–21.
2. **grip** (5k, uses almost nothing) — after row 19 and its own `linux_input` move; a day. Proves the process for a tiny app.
3. **inn** (14k, active) — after rows 23–24. The first server + SQL consumer; the migration will find the gaps in both.
4. **nema** (66k, active) — after rows 23, 25, 26 and its own Ladybug move. Largest active consumer; last of the active ones.
5. **Pie** (35k, active) — after rows 22, 25, 27. Pie's needs (WebSocket, audio streams, Codex Realtime) are the most specialised; it migrates when those rows are resolved and not before (row 27 needs no package).
6. **taumel, p-doom** — dormant since August; they stay on `v1` indefinitely and migrate only if they wake up. taumel receives crux/signal/jsoo when it does.

## What this means for the kernel's final size

eta-next at the end of this plan: core, test, json, observability (+otel), app, process, ipc, rpc, http (client, server, ws, tls, routing), ai (core, System One, chat, Responses/embeddings/audio, Codex Realtime), sql (sqlite + DSL), blocking. Row 27 is closed without a stream package: Eio/Seq and consumer-owned admission state suffice. Roughly a third of v1's line count, every package with at least one consumer, no drivers for single databases, no UI kernel, no jsoo, no HTTP/2 until pulled.

## Appendix: measurements (2026-09-27)

v1 package sizes (library lines, `Effect.t` references): http 13.8k/146 (h2 codec 4.6k/0, ws codec 206/0, core 718/0, error 503/0, body 792/15, client 689/40); http_eio 14.1k/314 (server.ml 773/0, h1_server_connection 1.5k/46, ws 1.4k/1, h2 747/23); http_tls_openssl 1.4k/0; http_service 703/50; sql 4.8k/90; sql_dsl 3.2k/0; ppx_sql 461/0; ai 27.4k/366 (openrouter 1.6k/31, openai 7k/44, anthropic 860/6); otel 3.8k/63; otel_eio 1k/10; stream 2.1k/206; blocking 1.3k/23; par 1.8k/16; cache 928/27; router 1.6k/0; crux 11.7k/426; signal 7k/7; signal_map 792/0; jsoo 1.1k/17; http_js 748/65.

Consumer references by module family: see the table above; raw counts in the session that produced this document.

## Executed: the switch to master (2026-09-29)

- **Old master** (the v1 line) was `5b3affc840010c1ffa3420ad30df21a46f08bd87` ("feat(json): eta_json package owns the unchecked Yojson helpers", 2026-09-26). It is the `v1` tag, and the tag is the whole boundary: both dormant consumers pin revisions, not a branch, so no `v1` branch was created.
- **The switch commit** is `5b09ee47f92a3bc7ea5ee18b8e37c03f38b9594d` (2026-09-29 09:15, "Row 31 done: nema on eta-next and in production") — the `eta-next` branch tip, which `master` was reset to. The commit that records this is the docs commit on top of it, and it is the revision the consumers are locked to. Nothing was pushed.
- **Every active consumer** moved its Eta input from `git+file:///home/ribelo/projects/ribelo/ocaml/Eta?ref=eta-next` to `?ref=master`, its `ETA_PATH` default from `../ocaml/eta-next` to `../ocaml/Eta`, and its eta lock node with `nix flake update eta` (that node only). The locks first moved to the switch commit and then to the docs commit that carries this record — master's tip; the two differ only in this file.

| Consumer | lock before | lock after | gates, 2026-09-29 (run on the switch commit) |
| --- | --- | --- | --- |
| grip | `14f80b76` | master tip | `dune build @install`, `dune test` (38 tests), `dune build @fmt` green |
| inn | `14f80b76` | master tip | `dune build @install`, `dune test` (45 tests) green; no `@fmt` alias (no `.ocamlformat`) |
| nema | `90f17cf0` | master tip | `dune build @install` green; `dune runtest --force` green (36 suites) |
| Pie | `ec352e9b` | master tip | `dune build @install` and `@fmt` green; `dune test --force` green with `EIO_BACKEND=posix` (35 suites). Without it the suite is red on `io_uring_queue_init` `ENOMEM`: `ulimit -l` is 8 MiB on this machine, Pie's service unit already sets `EIO_BACKEND=posix`, and the failures do not involve Eta |
| Leash | `ec352e9b` | master tip | `dune build @install` green; `dune test` red only in row L37's `extr-tkco books.toscrape.com example`, whose playbook the row-L40 worker is editing in that tree; `@fmt` not run (that worker is editing the tree) |

- **taumel and p-doom stay on v1** and needed no repin: neither has an Eta flake input. taumel pins `eta-revision` `1589b3e5033ec1552d9ef0a6f55a248aaf1a814f`; p-doom pins `builtins.fetchGit { rev = "4197be98d5e56a3bfd22a904ec4d84cb8fc69ddc"; }`. Both revisions are on the tagged v1 history, so moving master changes neither build. p-doom's dev-shell default `ETA_PATH` (`../ocaml/Eta`) now names the master checkout: its pinned Nix package build is unaffected, but `eta-opam-install-ox` run from that default would install master's packages into the shared switch.
- **Left for the lead, in order:** run `eta-opam-install-ox` from `/home/ribelo/projects/ribelo/ocaml/Eta` — the `5.4.0+ox` switch still pins every eta package to `git+file:///home/ribelo/projects/ribelo/ocaml/eta-next#90f17cf0…` — then remove the eta-next worktree and delete the `eta-next` branch. The worktree was kept for exactly that reason.
- Two facts about the Eta main checkout, recorded so nobody is surprised: a pre-existing uncommitted draft (eta_process / eta_ipc / system_one, written 2026-09-26) was preserved on branch `wip/eta-main-checkout-2026-09-26` before the switch, and 505 v1-era untracked files remain under `.scratch/research/` because the directories' tracked `.gitignore` files belonged to the v1 tree.
