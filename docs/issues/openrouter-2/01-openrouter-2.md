---
status: completed
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

## Verified

Delivered: `Responses.response` keeps `id`, `model`, `status` and `text` and gains
`output : output list` — `Output_text of string | Function_call of {name; call_id} |
Refusal of string | Other of string`, every item of the reply's `output` array in order,
none dropped — plus `deliverable : response -> (string, rejection) result` with
`[ `Not_completed of string | `Tool_continuation of {name; call_id} | `Refusal of string |
`Other of string ]`, which is `Ok text` only for `status="completed"` text-only replies.
A function call's arguments are deliberately not decoded: refusal needs its identity, not
its payload. `Audio.body` and `Audio.create` take `?max_request_bytes` (default 8 MiB,
`Audio.max_request_bytes` unchanged) checked against the whole encoded multipart body
before any I/O, and a non-positive bound raises `Invalid_argument`.

Tests: `test/ai/test_openrouter.ml` `Responses output kinds ^nor-pn0b` (Pie's
completed+function_call fixture beside valid text, a refusal item, an unmodelled
`reasoning` item and an `incomplete` status — each distinguishable in `output` and
refused by `deliverable`, while completed text-only is delivered) and `audio request
bound ^nor-474w` (below/at/above one encoded bound, a non-positive bound raising, and a
refused `create` opening no connection).

Gates: scoped `lib/ai_openrouter` + `test/ai/test_openrouter.exe` green under
`DUNE_BUILD_DIR=_build_nor2`, and `dune build @install`, `dune test --force` (23 suites)
and `dune build @fmt` green on the tree. Consumers: Leash, grip and inn do not use
`eta_ai_openrouter`, so nothing changes for them; Pie's U3 reads `deliverable`/`output`
instead of trusting `status` and `text`, and passes its own capture bound to
`Audio.create ~max_request_bytes`.
