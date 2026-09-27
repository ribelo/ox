# Eta

Eta is a private application kernel for OCaml services: typed errors, structured failure causes, Eio concurrency with scoped resources, one door for every process, and the protocol clients and servers those services need. It is built on OxCaml and Eio, in direct style.

This branch (`eta-next`) is a fresh start. The previous design — an effect blueprint interpreted by a runtime layered over Eio — lives on the `v1` tag and branch for the applications that still use it. `docs/why-next.md` explains the change and how code is written here.

Nothing enters this tree without a consumer. The first consumer is Leash (`/home/ribelo/projects/ribelo/leash`).

- `CONTEXT.md` — vocabulary
- `docs/why-next.md` — why v1 was abandoned, how direct style works here, where effect handlers fit
- `docs/adr/` — the decisions that are hard to reverse
- `eta` — core typed failures, scoped resources, schedules, and Eio concurrency
- `eta_test` — Eio mock clocks, scripted I/O and processes, and Exit assertions
- `eta_json` — unchecked Yojson accessors: bounded parse, builders, member reads (shapes we do not own, like CDP)
- `eta_http` — bounded HTTP/1.1 client with verified OpenSSL TLS over Eio
- `eta_otel` — caller-scoped OTLP JSON logs and completed spans over a borrowed HTTP client
- `eta_ai` — the AI clients' shared transport: bearer auth from a redacted key, a bounded JSON POST with two attempts on transport failure/429/529, and the six typed failures
- `eta_ai_systemone` — the fail-closed System One (JEV) client: typed choice and score questions, answers decoded field by field, the reply's model checked, both endpoints
- `eta_ai_chat` — the text helper's one call: a non-streaming OpenAI-compatible chat completion with `response_format: json_object` and reasoning off, over the same transport and errors
- `eta_ai_openrouter` — OpenRouter's Responses call with WAV audio, indexed text embeddings, and the WAV transcription upload
- `eta_ai_realtime` — a scoped Codex Realtime WebSocket session: authenticated connect, JSON events both ways, close
- `eta_rpc` — scoped request/reply correlation over message streams
- `eta_ipc` — private Unix control listeners with scoped socket ownership and bounded peers
- `eta_process` — scoped Unix children with graceful termination and scheduled supervision
- `eta_blocking` — bounded native worker calls over Eio system threads, with explicit cancellation and drain policies
- `eta_observability` — structured logs with fiber-local fields, redacted secrets, spans, and one JSON object per line for the journal
- `eta_app` — one Door for Eio services: TOML configuration decoded by the config type's derived codecs, status and a journal logger
- `ppx_yojson_minimal` — minimal `[@@deriving yojson]` preprocessor for OxCaml: a build-time text preprocessor on `compiler-libs`, no ppxlib

Shapes we own are plain types with `[@@deriving yojson]`; `eta_json` stays for JSON whose
shape belongs to a peer (`docs/adr/0008-types-are-the-schema.md`).
