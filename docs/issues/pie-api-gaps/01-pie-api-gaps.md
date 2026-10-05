---
status: completed
package: ox_ai, ox_ai_openrouter, ox_http
consumer: Pie (dict-dq3o, dict-ldo9, etagap-jk25, etagap-3uxz, etagap-utb3, etagap-g1ip)
---

# Pie provider calls without local protocol workarounds

## Problem Statement

Pie documents these gaps in [missing-ox-api.md](/home/ribelo/projects/ribelo/pie/docs/missing-ox-api.md): Responses fixes audio to WAV and a hidden 4 MiB request ceiling; reasoning output prevents delivery; text-only correction constructs its own JSON; provider calls cannot select response-progress deadlines; WebSocket establishment was wrapped in a total timeout. Pie is the consumer and remains read-only during this delivery.

## User Stories

1. As Pie's audio Responses caller, I want to select WAV or MP3 with the bytes, retaining WAV as the default and excluding unsupported OGG, so that MP3 dictation needs no local audio encoder (dict-dq3o). ^oxpie-a4m7
2. As Pie's provider caller, I want to bound the complete encoded request myself, refusing oversize uploads before I/O and reporting the effective limit on provider 413, so that the capture budget, not a hidden 4 MiB ceiling, controls admission (dict-dq3o). ^oxpie-b6q2
3. As Pie's text consumer, I want reasoning output retained for inspection but skipped by the delivery verdict, while status, tool calls, refusals and unknown output still disqualify delivery, so that reasoning-enabled Gemini returns its message text without a local filter (dict-ldo9). ^oxpie-c8r5
4. As Pie's correction caller, I want rendered instructions, one user input message, temperature and optional reasoning effort in a text-only Responses call using the existing decoder and delivery verdict, so that the local encoder and JSON transport call disappear (dict-ldo9). ^oxpie-d3t9
5. As Pie's Responses caller, I want a response idle deadline that resets on incoming progress and remains separate from the total deadline, so that long progressing replies survive while stalled headers or bodies time out (etagap-jk25, etagap-3uxz). ^oxpie-e5v1
6. As Pie's direct transcription caller, I want the same response idle policy and its existing upload bound, so that the broad total-effect workaround is unnecessary where progress policy is appropriate (etagap-jk25, etagap-3uxz). ^oxpie-f7w4
7. As Pie's Realtime caller, I want one establishment deadline covering DNS, TCP, TLS and HTTP upgrade, but not the established stream, so that the connection wrapper can be removed (etagap-utb3, etagap-g1ip). ^oxpie-g2x6

## Implementation Decisions

- Every change is additive. Existing audio request record literals remain valid: `wav` retains its legacy name; optional `audio_format` on `encode`/`create` defaults to `Wav`, with `Mp3` as the other supported constructor. Optional audio `instructions` separates a rendered prompt from the existing user input.
- `text_request`, `encode_text` and `create_text` share request framing, response decoding and `deliverable` with audio. Optional response-size limits let Pie preserve its existing reply budget.
- `Other "reasoning"` remains visible in `response.output`; `deliverable` skips it without changing the public output variant or response record. No reasoning text is projected into `response.text`.
- Serialized JSON bounds cover base64 and framing; transcription already exposes its multipart bound. Defaults and transport retry behavior stay unchanged.
- The gap document names v1's `Ox_http.Request.Response_idle_timeout.t`. Current Ox uses `Ox_http.Client.request ?response_idle:Ox.Duration.t`; expose that same modern type/name through shared AI transport and provider calls rather than restore a retired request module. Incoming reads reset the idle deadline; total deadlines still bound the complete call and retry backoff. Cancellation propagates and closes each request socket.
- `Responses.create/create_text ?timeout:Ox.Duration.t` exposes the existing per-attempt budget without changing its ten-second default. The earliest of this cap, the response idle deadline and the remaining total deadline wins; the latter still includes retries and backoff. Pie can raise the attempt cap alongside a longer idle policy so progressing replies are not cut off at the historical default.
- After row 57 (`e7054a73`), `Ox_http.Ws_client.connect ?establishment_timeout:Ox.Duration.t` already covers establishment with a 10-second default. Reuse it, document it for Pie and verify it; do not add a second timeout API.

## Pie API mapping

| Pie gap / retired name | Public current Ox API |
| --- | --- |
| WAV-only Responses (dict-dq3o) | `Ox_ai_openrouter.Responses.audio_format` (`Wav` or `Mp3`); `Responses.encode` and `Responses.create ?audio_format`, default `Wav`. Existing `request.wav` carries the selected bytes. |
| Hidden encoded request ceiling (dict-dq3o) | `Responses.create/create_text ?max_request_bytes ?max_response_bytes`; the complete serialized JSON is bounded, including base64 and framing. `Audio.create ?max_request_bytes` already bounds multipart uploads. |
| Local reasoning filter (dict-ldo9) | `Responses.deliverable` ignores `Other "reasoning"` without removing it from `response.output`; tools, refusals, unknown kinds and incomplete status still fail closed. |
| Local text encoder and private `Common.post` (dict-ldo9) | `Responses.text_request`, `Responses.encode_text`, `Responses.create_text`: separate `instructions`, one user `input_text`, optional temperature, text format and reasoning effort. |
| `Ox_http.Request.Response_idle_timeout.t`, lower-case provider names and `Ox.Effect.timeout_as` (etagap-jk25, etagap-3uxz) | `Responses.create/create_text ?response_idle:Ox.Duration.t` and `Ox_ai_openrouter.Audio.create ?response_idle:Ox.Duration.t`; transcription is `Audio`, not a separate `transcription` module. Shared `Ox_ai.Transport.post_json` forwards the modern HTTP option. The caller can also raise `Responses.create/create_text ?timeout` above its historical ten-second per-attempt default for long progressing replies; the total `deadline` remains independent. |
| `Ox_http_eio.Ws.Client.connect` / total-effect wrapper (etagap-utb3, etagap-g1ip) | Existing `Ox_http.Ws_client.connect ?establishment_timeout:Ox.Duration.t`: one DNS/TCP/TLS/upgrade budget, default ten seconds, no stream-lifetime deadline. |

No retired `Ox.Effect`, `Ox_http.Request` or `Ox_http_eio` compatibility surface is restored. Pie can replace its wrappers with the current public provider and transport APIs when it adopts this delivery.

## Testing Decisions

- Local fake HTTP servers record WAV/MP3 and text-only request JSON; no real provider calls. Test omitted optional fields, non-finite temperature, and shared decode/verdict behavior.
- Exercise below/at/above complete request byte bounds and provider 413 limits, including no connection on local refusal, text-only JSON, the already-supported multipart path, and exact/oversize caller-selected response bounds without retry.
- Reasoning beside message text delivers only the message; reasoning beside a tool call/refusal and non-completed status still refuses; other kinds remain refused.
- Stalled headers, stalled bodies, progressing bodies longer than the idle budget, and the separate total deadline are tested on both Responses and transcription. Audio/text Responses also verify a caller-selected short per-attempt cap fails, a raised cap permits the same progressing reply, and the total deadline still takes precedence.
- Mock network fixtures verify stalled DNS/TCP work is cancelled; local WebSocket fixtures verify stalled upgrade and TLS handshake hit the same establishment deadline, cleanup closes the socket, and traffic after establishment is not capped by that deadline.
- Every dune command is foreground under `timeout 900`, `DUNE_BUILD_DIR=_build_oxpie`, and `ulimit -v 16777216`; caps-gate runs without the memory cap. Required gates: `@install`, `dune test`, `@fmt`, caps-gate. Install only into `/tmp/ox-pie`; build Leash, nema, inn and grip against that private prefix, with nema's prefix built in its own Nix shell. Delete generated private build directories afterward. Never run ox-opam-install, change installed services/binaries, edit Pie/Leash or commit.

## Verification

- Required Ox gates passed: `dune build @install`, full `dune test`, `dune build @fmt`, and `scripts/caps-gate`. All dune runs were foreground with the 900-second timeout, private build directory and 16 GiB virtual-memory ceiling described above. Caps-gate ran uncapped with `EIO_BACKEND=posix` because this host could not allocate an io_uring queue; its reported lexical fallbacks passed.
- [Pie offline API suite](../../../test/ai/test_pie_api.ml): nine passing cases; existing [OpenRouter compatibility suite](../../../test/ai/test_openrouter.ml): nine passing cases; expanded [WebSocket suite](../../../test/http/ws_client/run.ml): 25 passing cases, including DNS/TCP cancellation, TLS/upgrade timeout socket cleanup, and established traffic past the establishment budget.
- `inn`, `grip` and `nema` build `@install` against the final private prefix, with `ocamlfind query ox_ai_openrouter` resolving to `/tmp/ox-pie/lib/ox_ai_openrouter`. Nema uses Ox rebuilt in its own Nix shell, preserves shell-provided `OCAMLPATH`, and adds the existing Ox-shell SQLite pkg-config directory without changing Nema or shared installations.
- Leash built green earlier against `/tmp/ox-pie`; final recheck is pending its concurrent BLOCKED-rescue edit, which introduced unrelated unused-variable warnings. That check belongs to the coordinating Leash delivery; it does not indicate an Ox API incompatibility.
- Generated private build directories in Ox, Leash, inn, grip and nema, plus `/tmp/ox-pie`, were removed after verification. Pre-existing build trees were preserved.
- No provider calls, consumer source edits, shared opam changes, installed binary/service changes, or commits. Existing untracked `.pie/` remains untouched.

## Replay-safety supersession (2026-10-05)

The independent approved [replay-safety stories](<../adaptive-retry/01-adaptive-retry.md>) supersede only the automatic replay default described above (safe-o2b6, safe-a5mq, safe-3o27, safe-s51t). Ox_ai.Transport.post_json defaults to Never_replay, including ambiguous failures and 429/529 responses without a proof of non-commit. Allow_duplicate_effects is explicit permission, not proof of idempotency. Attempt budgets, response bounds, error classification and external cancellation retain their contracts; old two-attempt behaviour is available only with explicit replay permission. Existing callers are not mechanically opted in. The original story IDs remain historical anchors and are not renamed or reused.
