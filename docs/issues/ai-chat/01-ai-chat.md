---
status: completed
package: eta_ai_chat
consumer: Leash milestone 5 (drive-ls3c, drive-fh1h: the text helper) and L32 (run-obtt,
  etagap-pl4n: the planner turn's cost)
---

# Minimal OpenAI-compatible chat completion (JSON object output)

## Problem Statement

The drive loop's text helper is one non-streaming chat completion with `response_format: json_object` and reasoning off, against an OpenAI-compatible endpoint (OpenRouter by default). eta-next has no chat client; v1's is 20k lines across twelve providers and is not pulled.

## Solution

`eta_ai_chat`: one `complete` call — model, system and user messages, `max_tokens`, `response_format`, reasoning controls — returning the first choice's content as a string plus usage, over `eta_http` and the `eta_ai` core.

## User Stories

1. As a service author, I want `Chat.complete client ~deadline ~model ~messages ?max_tokens ?json_object ?reasoning ()` returning `(completion, error) result` with `content` and usage, so that the text helper is one call. ^nchat-dys0
2. As a service author, I want `~reasoning:`Disabled` to send OpenRouter's `reasoning: {enabled: false}` and `~reasoning:(`Effort "low")` its effort form, with omission sending nothing, so that reasoning is explicitly off on the hot path. ^nchat-6kd8
3. As a service author, I want `~json_object:true` to send `response_format: {type: "json_object"}`, so that the helper's output can be required to be JSON. ^nchat-02vr
4. As a service author, I want the same fail-closed decoding, bounds, two-attempt policy and typed errors as the System One client, sharing the `eta_ai` core, so that the two clients behave identically under failure. ^nchat-wtog
5. As an operator, I want usage logged at debug per completion, so that the helper's spend is visible next to JEV's. ^nchat-96zw
6. As a test author, I want a fake chat server under `test/ai/` and one live smoke behind an environment flag, so that the client is proven offline and once for real. ^nchat-kk3g
7. As a service author, I want the provider's reported cost of a chat completion, so that planner and helper spend is accounted. ^nchat-qu3j

## Implementation Decisions

- Endpoint default `https://openrouter.ai/api/v1/chat/completions`; base URL configurable so DeepSeek or a local server works.
- Only what the text helper uses; no tools, no streaming, no images.
- `usage.cost` — the provider's own USD number beside the token counts — is an optional
  member (^nchat-qu3j). The endpoint is OpenAI-compatible, not OpenRouter, so a server that
  reports only tokens is not sending a broken reply: an absent cost (or a `null`) reads
  `None`, never `0.`, and the debug line then carries no `cost` field. A cost that is
  present and not a number is refused with its path, like every other wrongly typed member
  (^nchat-wtog). A caller reads it at `Codecs.completion.usage.cost`, beside the tokens,
  as the System One client's `Codecs.usage.cost` is read.

## Testing Decisions

- One test per story against the fake server.

## Out of Scope

Streaming, tool calls, multimodal, provider-specific parameters beyond reasoning.
Image request parts are delivered separately in [ai-chat-images](../ai-chat-images/01-ai-chat-images.md).

## Verified

`nix develop -c dune build @install`, `dune test` (29 cases in `test/ai/`: one call and
the request it writes, the reasoning and JSON-object forms, fail-closed decoding, both
bounds, the retry matrix, the usage log, the provider's cost — reported, absent and
non-numeric — and the fake chat server) and `dune build @fmt` are green; the live smoke
is opt-in (`ETA_AI_LIVE_SMOKE=1` with `OPENROUTER_API_KEY`, `ETA_AI_LIVE_CHAT_MODEL` and
`ETA_AI_LIVE_CHAT_ENDPOINT` overrides) and was not run here.
Three decisions are recorded rather than dropped: `~endpoint` is the full
`chat/completions` URL, exactly as the System One client's `~endpoint` is, so a consumer
holding a base URL appends the route; `Model_mismatch` is never returned — the model is
per call and a provider may route it, so the reply's model travels in
`Codecs.completion.model` for a caller that pins one; and `usage.cost` is optional and
fail-closed in the same breath — a reply that reports no cost reads `None` (never `0.`,
because a chat endpoint is OpenAI-compatible and not OpenRouter) while a cost that is
present and not a number is refused with its path (^nchat-qu3j).
