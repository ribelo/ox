---
status: completed
package: eta_ai (new: shared transport types) and eta_ai_systemone
consumer: Leash milestone 5 (drive-zml5, drive-e7oi, drive-kh2u, drive-7tvn)
---

# System One client (JEV) over eta_http

## Problem Statement

JEV answers choice questions over a JSON state with probability distributions. Leash's drive loop needs exactly that call, fail-closed, with a bounded request, a bounded response, a deadline, and at most two attempts on transport failure. The contract exists twice already — SmartRouter's TypeScript client (which only checks the top-level shape) and v1's `ai-openrouter-systemone` ticket (never implemented). jev-ultrafast posts to `https://api.typesafe.ai/v1/systemone`; OpenRouter proxies the same contract at `/api/v1/systemone`. Both must work.

## Solution

`eta_ai_systemone`: typed request (`state : Yojson.Safe.t`, `questions : (name * question) list` with choice and score questions), typed response (answers by name with choice/probabilities/confidence or score/legend/probabilities/confidence, usage, id, provider), one `evaluate` over `Eta_http.Client`, endpoint and model configurable, bearer key as `Redact.t`.

## User Stories

1. As a service author, I want `Systemone.create ~http ~endpoint ~api_key ~model` and `Systemone.evaluate client ~deadline ~state ~questions` returning `(response, error) result`, so that a decision is one call. ^nso-5hom
2. As a service author, I want choice questions (`instructions : Yojson.Safe.t`, `criteria : (key * string option) list`) and score questions (`instructions`, ordered `criteria : string list`) encoded exactly as System One expects, so that the request matches the contract. ^nso-jz8v
3. As a service author, I want the response decoded fail-closed — model, every named answer with its discriminant and required fields, usage with input_tokens/output_tokens/cost — rejecting missing or wrong-typed fields with ``Invalid_response of issue` rather than defaulting, so that a malformed answer never drives an action. ^nso-megl
4. As a service author, I want the reply's `model` checked against the configured model and a mismatch reported as ``Model_mismatch`, so that a provider substitution is caught. ^nso-ttfj
5. As a service author, I want a request whose serialized body exceeds 4 MiB refused before sending with ``Input_too_large`, and a response over 1 MiB rejected, so that bounds hold on both sides. ^nso-pflg
6. As a service author, I want at most two attempts, the second only after a transport failure, a timeout of the first attempt, or HTTP 429/529, with a short backoff on the clock, all inside the caller's deadline, so that a flaky network gets one more chance and nothing else does. ^nso-zmfp
7. As a service author, I want typed errors — ``Unavailable`, ``Timeout`, ``Authentication`, ``Invalid_response`, ``Input_too_large`, ``Model_mismatch` — each carrying whether a retry is reasonable, so that the drive loop maps them to its own status. ^nso-77t7
8. As an operator, I want each evaluation's usage and cost logged at debug through the logger with the request id, so that spend is visible. ^nso-61ka
9. As a test author, I want a fake System One HTTP server under `test/ai/` scripting answers, malformed answers, 429, 5xx, slow bodies and a wrong model, so that every story runs offline; plus one live smoke behind an environment flag with a real key. ^nso-hcfr
10. As a kernel maintainer, I want the shared pieces (bearer auth header, JSON POST helper, error mapping from `Eta_http` errors) in a small `eta_ai` core so that the chat client (next spec) reuses them, so that the two clients do not diverge. ^nso-y4rw

## Implementation Decisions

- Contract source: SmartRouter's `src/jev.ts` for the TypeScript shape and jev-ultrafast `model.py` at commit `1231850a` for the state and question shapes that JEV was trained on; both are copied into this spec's directory as `reference/` for the implementer.
- Endpoint default `https://openrouter.ai/api/v1/systemone`; `https://api.typesafe.ai/v1/systemone` accepted; the key is whichever the endpoint needs.
- No Yojson helper duplication: `Eta_json.Of_json` for decoding.

## Testing Decisions

- `test/ai/`: one test per story against the fake server. The clock is Eio's real one, not
  the mock one: advancing a mock clock needs the test fiber to run while the client's
  socket wait needs the scheduler to poll, and one domain cannot do both. The backoff
  (100 ms), an attempt's cap (50 ms) and a short deadline are therefore real and short —
  the whole suite costs under a second.

## Out of Scope

Score-question consumers, streaming, batching, any other provider endpoint.

## Verified

`nix develop -c dune build @install`, `dune test` (34 cases in `test/ai/`: contract,
bounds, fail-closed decoding, retry matrix, logging) and `dune build @fmt` are green; the
live smoke is opt-in (`ETA_AI_LIVE_SMOKE=1` with `OPENROUTER_API_KEY`) and was not run
here. Two deviations from `reference/jev.ts` are recorded rather than dropped: the 400/422
context-overflow heuristic is not implemented (that reply is `Invalid_response`), and
``Unavailable`` carries the reference's two forms through `retryable`.

## Replay-safety supersession (2026-10-05)

The later approved [Ox safety specification](<../ox-safety-gate/01-ox-safety-gate.md>) and [retry-safety ticket](<../ox-safety-gate/19-retry-safety.md>) supersede only the automatic replay default described above (safe-o2b6, safe-a5mq, safe-3o27, safe-s51t). Ox_ai.Transport.post_json defaults to Never_replay, including ambiguous failures and 429/529 responses without a proof of non-commit. Allow_duplicate_effects is explicit permission, not proof of idempotency. Attempt budgets, response bounds, error classification and external cancellation retain their contracts; old two-attempt behaviour is available only with explicit replay permission. Existing callers are not mechanically opted in. The original story IDs remain historical anchors and are not renamed or reused.
