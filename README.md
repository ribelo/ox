# Ox

Ox is a private application kernel for OCaml services: typed errors, structured failure causes, Eio concurrency with scoped resources, one door for every process, and the protocol clients and servers those services need. It is built on OxCaml and Eio, in direct style.

This branch (`master`; it was the `eta-next` branch until the switch of 2026-09-29) is a fresh start. The previous design — an effect blueprint interpreted by a runtime layered over Eio — lives on the `v1` tag for the two applications that still use it (taumel, p-doom). `docs/why-ox.md` explains the change and how code is written here.

Nothing enters this tree without a consumer. The first consumer is Leash (`/home/ribelo/projects/ribelo/leash`).

- `CONTEXT.md` — vocabulary
- `docs/why-ox.md` — why v1 was abandoned, how direct style works here, where effect handlers fit
- `docs/adr/` — the decisions that are hard to reverse
- `ox` — core typed failures, scoped resources, schedules, Eio concurrency, and the rest of Ox's floor: `Rate_limiter` (use it for per-site or per-model limits instead of a sleep), `Channel` and `Select`, `Resource` (`docs/design/ox-floor.md`; `Flow` is designed in `docs/design/flow.md`)
- `ox_test` — Eio mock clocks, scripted I/O and processes, and Exit assertions
- `ox_json` — unchecked Yojson accessors: bounded parse, builders, member reads (shapes we do not own, like CDP)
- `ox_http` — bounded HTTP/1.1 client with verified OpenSSL TLS over Eio
- `ox_otel` — caller-scoped OTLP JSON logs, completed spans and metric instruments (counter, up-down counter, histogram) over a borrowed HTTP client, with resource attributes and collector headers
- `ox_ai` — the AI clients' shared transport: bearer auth from a redacted key, a bounded JSON POST with two attempts on transport failure/429/529, and the six typed failures
- `ox_ai_systemone` — the fail-closed System One (JEV) client: typed choice and score questions, answers decoded field by field, the reply's model checked, both endpoints
- `ox_ai_chat` — the text helper's one call: a non-streaming OpenAI-compatible chat completion with `response_format: json_object` and reasoning off, over the same transport and errors
- `ox_ai_openrouter` — OpenRouter's Responses call with WAV audio, indexed text embeddings, and the WAV transcription upload
- `ox_ai_realtime` — a scoped Codex Realtime WebSocket session: authenticated connect, JSON events both ways, close
- `ox_rpc` — scoped request/reply correlation over message streams
- `ox_ipc` — private Unix control listeners with scoped socket ownership and bounded peers
- `ox_process` — scoped Unix children with graceful termination and scheduled supervision
- `ox_blocking` — bounded native worker calls over Eio system threads, with explicit cancellation and drain policies
- `ox_observability` — structured logs with fiber-local fields, redacted secrets, spans, and one JSON object per line for the journal
- `ox_app` — one Door for Eio services: TOML configuration decoded by the config type's derived codecs, status, a journal logger and the telemetry hook that adds reporters and span IDs to it
- `ppx_yojson_minimal` — minimal `[@@deriving yojson]` preprocessor for OxCaml: a build-time text preprocessor on `compiler-libs`, no ppxlib

Shapes we own are plain types with `[@@deriving yojson]`; `ox_json` stays for JSON whose
shape belongs to a peer (`docs/adr/0008-types-are-the-schema.md`).
