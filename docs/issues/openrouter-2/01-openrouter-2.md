---
status: ready-for-agent
package: eta_ai_openrouter
consumer: Pie migration (pienext-93ym, pienext-osw0)
---

# OpenRouter Responses and audio: keep what a caller must refuse, let the caller bound the upload

## Problem Statement

`Responses.response` is `{id; model; status; text}`; a completed reply that also carries a `function_call` (or other non-text output) loses that item, so a caller that must refuse tool continuation cannot. `Audio` hard-codes an 8 MiB multipart ceiling, below Pie's admitted 64 MiB PCM capture.

## User Stories

1. As a Responses caller, I want the decoded response to report every output item's kind (message text, function call, refusal, other) — or a typed non-deliverable outcome — so that a completed reply that asks for a tool is never delivered as text. ^nor-pn0b
2. As an audio caller, I want `Audio.body` and `Audio.create` to take an optional validated `max_request_bytes` (default unchanged), refusing an oversize body with a typed error before any network I/O, so that my own capture bound applies. ^nor-474w

## Implementation Decisions

- Pie's fixture (completed + function_call + valid text) must be distinguishable from completed text-only; nothing is silently dropped.
- The bound covers the whole encoded multipart body.

## Testing Decisions

- Local fake server: the Pie-shaped fixture, a refusal item, text-only; below/at/above a configured bound.
