---
status: completed
package: eta_ai_openrouter, eta_ai_realtime
consumer: Pie (OpenRouter STT and Codex Realtime), nema (OpenRouter embeddings)
---

# OpenRouter Responses, embeddings and audio; Codex Realtime session

## Problem Statement

Pie builds a Responses request with user text and WAV audio, checks the finish outcome and extracts text, and uses direct speech-to-text upload as a fallback. Its Codex path needs an authenticated scoped WebSocket session. nema submits individual and batched text embeddings with dimensions and checks each returned index and vector. The existing chat client does not implement these protocols.

## Solution

Provide focused endpoint clients over eta_ai's bounded transport, with typed wire shapes, plus an independently scoped Realtime session over eta_http's WebSocket client. Keep Pie-specific capture, prompts, transcript assembly and OAuth refresh in Pie.

## User Stories

1. As Pie, I want a non-streaming Responses call with model, user text and WAV audio, structured JSON text output, reasoning effort and finish markers, so that I can transcribe or translate and reject incomplete outcomes. ^air2-rsp1
2. As nema, I want one or many text embeddings with model and dimensions, indexed float vectors and typed failures, so that I can check vector order and size in my own retrieval layer. ^air2-emb2
3. As Pie, I want a bounded OpenRouter speech-to-text WAV upload with language and prompt controls, so that direct transcription remains available. ^air2-aud3
4. As Pie, I want to open an authenticated Codex Realtime WebSocket against a caller-selected endpoint, exchange JSON events and close with the caller's switch, so that its STT implementation owns the higher-level conversation. ^air2-rtm4
5. As an operator, I want offline fake-server coverage of success, invalid payloads and HTTP failures, plus a strictly opt-in live OpenRouter smoke, so that the endpoints are verified without network secrets in normal tests. ^air2-tst5

## Implementation Decisions

- Responses, embeddings and WAV multipart audio are separate endpoint modules inside eta_ai_openrouter; Codex Realtime lives in eta_ai_realtime instead of adding unrelated shapes to the eta_ai core. Realtime is a distinct WebSocket protocol, but stays in this row's single spec because it serves the same Pie migration.
- Per-call endpoint overrides accept complete URLs; defaults target OpenRouter's v1 routes. Realtime accepts caller-supplied Authorization and protocol headers rather than implementing Pie's OAuth lifecycle.
- Echo v1's pure wire layouts, but use ppx_yojson_minimal for fixed records and Eta_json.Of_json for dynamic content. Effectful calls are direct Eio style.

## Testing Decisions

- Local daemon fake server and real short clock; no live requests unless ETA_AI_LIVE_SMOKE=1 and OPENROUTER_API_KEY is present. Never log keys.

## Out of Scope

Streaming Responses, tools, images, nine other providers, Pie-specific PCM conversion, OAuth token refresh, transcript state machine and nema vector validation.

## Verified

Scoped targets are green under `DUNE_BUILD_DIR=_build_ai2`: `eta_ai_openrouter` and
`eta_ai_realtime` build, `dune test test/ai/test_openrouter.exe` passes six offline
cases over the local fake server and the real short clock (the Responses WAV wire,
indexed embeddings, the audio multipart upload, the failure matrix — 401, 413, 5xx and a
non-JSON 2xx body — strict decoding, and the Realtime handshake, masked client event and
close), and `dune build @fmt` is clean on this row's files. The live smoke is opt-in
(`ETA_AI_LIVE_SMOKE=1` with `OPENROUTER_API_KEY`) and was not run here; the
repository-wide gates are the lead's. Two decisions are recorded rather than dropped:
`Session.connect` forwards `?protocols` and `?ca_file` because Pie negotiates the
Realtime subprotocol and passes `SSL_CERT_FILE` today, and the audio upload maps its own
statuses (401, 413, other non-2xx) because `Transport.post_json` is JSON-only.
