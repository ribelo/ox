---
status: todo
category: enhancement
package: ox_http
consumer: Ox, Exergy, Pie, Nema
blocked_by: []
---

# No duplicate external effect on retry

## Problem statement

A remote order or other money-moving operation may commit before its response is lost. Repeating the request can silently perform it twice. An attempt limit and a timeout do not prove non-commit; cancellation does not undo the remote operation.

Ox HTTP currently exposes a one-shot [Client.request](../../../lib/http/client.mli#L51-L84), not retry-enabled post/put exports. Generic [Retry.retry](../../../lib/ox/retry.mli) can repeat arbitrary work. [AI transport](../../../lib/ai/transport.mli#L42-L47) defaults to Never_replay; its explicit Allow_duplicate_effects is consent to duplicates, not an idempotency proof. This spec does not reinterpret that permission as safety.

## Stories

1. As an order sender, I want retry-enabled POST/PUT signatures to require an idempotency token, so that omission fails compilation instead of silently duplicating money-moving effects. ^safe-z76e
2. As a caller, I want all attempts of one logical operation to share its token and request identity, so that a lost response does not become a new external operation. ^safe-boj2
3. As an operator, I want uncertain commits refused for endpoints without a sufficient deduplication contract, so that a token-shaped string does not pretend to prevent duplicates. ^safe-cn7g

## Requirements

- The Ox HTTP retry API shall require a caller-supplied opaque idempotency token in every retry-enabled POST and PUT signature. ^safe-k8e5
- When retrying one logical external operation, the Ox HTTP retry API shall reuse that operation's token bound to the same endpoint, method and payload across every attempt. ^safe-v6ek
- If an endpoint has no explicit token-deduplication contract covering the operation and remaining retry window, then the Ox HTTP retry API shall refuse automatic replay of a POST or PUT whose remote commit state is unknown. ^safe-dllv

## Acceptance

- Compile-negative calls to each proposed POST/PUT retry entry point omit the required token; token-bearing calls compile. No optional token, generated-per-attempt token or untyped header substitutes for the required argument.
- A fake deduplicating endpoint commits once, loses its first response, then receives a retry with the same key and request identity. It returns the original receipt; its external-effect count remains one.
- A changed endpoint/method/payload is not accepted as another attempt of that token's operation. An unsupported endpoint or expired deduplication window produces no automatic second send after an uncertain commit.
- Existing one-shot requests remain legal without a token. Ordinary cancellation propagates; retrying does not claim to undo it or establish non-commit.

## Scope and further notes

This replaces retired ticket 19 with one type-level spec only. No implementation, checker, tests, new module or existing retry signature is added by this delivery. The future public post/put retry API must carry the required token argument; the existing one-shot API is not falsely described as already having those exports.

An opaque token is necessary, not sufficient: the endpoint contract must define its accepted key mechanism, operation binding and deduplication retention window. Arbitrary closures passed to generic Retry.retry and manually repeated one-shot requests are outside this API guarantee. Existing explicit consent to duplicate effects is not a route into the no-duplicate retry contract.
