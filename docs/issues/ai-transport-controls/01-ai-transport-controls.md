---
status: ready-for-agent
package: eta_ai, eta_ai_openrouter
consumer: nema row 31 (nemanext-l8so, nemanext-zl1v, nemanext-791b)
---

# Provider calls a caller can bound, attempt once, and schedule from Retry-After

## Problem Statement

`Eta_ai.Transport.post_json` caps replies at 1 MiB, retries twice with a hidden backoff and deadline, and discards response headers, so a 429's Retry-After becomes a generic retryable `Unavailable`. nema's embedding worker admits 8 MiB batches, runs its own 4-attempt / 500 ms exponential / 30 s policy, and persists the provider's Retry-After into durable job scheduling.

## User Stories

1. As an embeddings caller, I want `?max_response_bytes` on `Eta_ai_openrouter.Embeddings.create` (and the shared transport), default unchanged, so that a valid batch larger than 1 MiB is decoded by the typed client. ^nai-97as
2. As a caller with its own retry policy, I want to ask for exactly one attempt (e.g. `?max_attempts`, default 2, or `?retry:` a policy) with no hidden backoff inside my deadline, so that my own schedule is not multiplied. ^nai-337c
3. As a caller honouring throttling, I want a provider HTTP error to carry `retry_after : Eta.Duration.t option` parsed from `Retry-After` (delta-seconds and HTTP-date; invalid → None), so that durable work waits as the provider asked. ^nai-rjkq

## Testing Decisions

- Fake server: a 2 MiB embeddings reply under and over a configured bound; one attempt means one request; 429 with `Retry-After: 7` and with an HTTP-date; invalid value.
