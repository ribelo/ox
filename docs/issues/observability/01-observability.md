---
status: done
package: ox_observability
consumer: Exergy and existing Logger users
priority: P1
---

# Structured spans with result-derived completion fields

## Problem Statement

Logger already records typed result failures, defects and external interruption correctly. It only accepts fields known before the body executes. Exergy needs the returned HTTP status, sanitized provider outcome and row count attached to the same completed request/ingest span. An inner context binding expires before completion, and a separate log is not the same span.

## Solution

Extend the existing structured span operation with a narrow pure completion-fields function over its returned result. Keep the start/end lifecycle, context inheritance and result/exception behavior. Do not create a second tracer or a mutable span handle.

## User Stories

1. As a service author, I want `Logger.log logger level ~msg ?fields ()` producing a record with timestamp, level, message, fields and the fiber's inherited context, so that every line is structured. ^nobs-og4h
2. As a service author, I want `Context.with_fields [("tab", …); ("owner", …)] f` to attach fields to everything logged inside `f`, including in fibers forked inside, so that identity is not threaded by hand. ^nobs-2d4r
3. As an operator, I want the journal reporter to write one compact JSON object per line to stderr with a stable key order, so that `journalctl` output is greppable and parseable. ^nobs-ek28
4. As a test author, I want an in-memory reporter with a query by level and field, so that tests assert what was logged and what was not. ^nobs-rayu
5. As a service author, I want `Redact.t` values to print as `<redacted>` through every path (`pp`, JSON, string) and to carry the yojson codecs a derived record field needs (`yojson_of_t` redacts, `t_of_yojson` wraps a decoded string), so that a secret cannot leak by accident and is redacted by being of that type. ^nobs-iedi
6. As a service author, I want a per-logger minimum level and a rate limit for a named repeated message, so that a flapping component cannot flood the journal. ^nobs-262i
7. As a service author, I want `Logger.span name f` to log start and end with elapsed time and an outcome (ok, failed with cause summary), so that tracing exists as structured logs before any exporter. ^nobs-xovg
8. As a kernel maintainer, I want the package to depend on `eta`, `eio` and `eta_json` only, so that OTLP export is a later, separate package. Row 16 adds `yojson` for `Redact.t`'s codecs (^nnoschema-ifg0, admitted by ADR-0007); the ceiling is otherwise unchanged. ^nobs-6x58
9. As a service author, I want a completion-fields function over the returned result, so that a span can include data known only after its body finishes. ^nobs-pzpr
10. As a provider author, I want successful HTTP status and sanitized provider outcome on the completed request span, so that trace queries describe the actual response rather than only request inputs. ^nobs-uwrx
11. As an ingest author, I want successful row counts and other nonsecret result summaries on the existing span, so that one operation produces one searchable completion. ^nobs-tv72
12. As a provider author, I want completion fields derived from a typed Error as well as Ok, so that a known failed-response status is not lost from telemetry. ^nobs-yi3q
13. As a service author, I want the original returned value or typed error preserved without reconstruction, so that telemetry cannot change domain behavior. ^nobs-jc4q
14. As a service author, I want static fields on start and completion but result-derived fields only on completion, so that a pending operation never publishes guessed final data. ^nobs-3cck
15. As a kernel maintainer, I want logger base fields overridden by explicit static fields and those by completion fields, while kernel lifecycle fields always win, so that duplicate names have one deterministic meaning. ^nobs-ze6n
16. As a service author, I want completion extraction skipped when the body raises and external interruption/defects preserved with their backtraces, so that an absent result is never fabricated for telemetry. ^nobs-h6pt
17. As a service author, I want a raising completion extractor classified as a defect with one defect completion and its original backtrace, so that a telemetry callback bug is not hidden or reported as a provider error. ^nobs-wrzs
18. As a test author, I want one completion per span, redacted values and sibling/nested isolation under result extraction, so that final fields do not leak to unrelated requests. ^nobs-a0se

## Implementation Decisions

- Keep direct style and the existing typed-result span operation. One result-to-fields callback is sufficient; separate success/error APIs and a mutable span object would add unnecessary surface.
- The extractor is a pure summary function, called once after a normally returned result. It does not await, issue requests, mutate context or emit telemetry. A body exception has no result and never invokes it.
- Precedence is logger base fields < static span fields < completion fields < kernel-owned event/outcome/elapsed_ms/error fields. Use a provider-specific key such as http.outcome instead of replacing kernel outcome. Correlation IDs remain context controls.
- If extraction raises, propagate that defect/backtrace and emit at most one defect end record, never both a successful end and a defect end. Preserve the existing exception policy of the reporter; do not introduce swallowing or broad result conversion.
- No dependency on the OTLP exporter. Preserve redaction through every reporter and keep the logger nonparking under its existing contract. Update native call sites if the public span signature changes; no Eta-compatible overload.

## Testing Decisions

- Confirmed public seam: Logger with its memory reporter; additionally one configured Door/OTLP local-collector integration proves the computed fields belong to a completed exported span.
- Test Ok and typed Error, unchanged value/error identity, static versus completion timing, collision precedence, reserved fields, body defects, external Eio cancellation, and extractor defects with distinguishable backtraces. Assert one start/end pair, not just presence of an extra log.
- Use nested and sibling fibers to prove dynamic summaries stay local; after the span, no result field remains in inherited context. Test Redact values through memory, journal and OTLP-facing record conversion.
- Existing result-awareness tests remain valid. Test names cite new IDs and prove the absent completion hook fails before implementation.

## Out of Scope

A mutable span handle, OpenTelemetry SDK, provider error classification, exporter lifecycle, automatic HTTP instrumentation, metrics policy, and compatibility with Eta named/observed-result wrappers.

## Further Notes

- Audit 2026-10-04 at Ox 08c6fc8f; relevant source remained unchanged at 72af4cde. Original IDs are preserved. Historical delivery is not evidence for this new hook; this audit made no implementation changes.
- Evidence: [public span signature:202–209](<../../../lib/observability/logger.mli#L202-L209>) and [span lifecycle:264–306](<../../../lib/observability/logger.ml#L264-L306>).
- Consumer contracts: [Gateway tracing requirements:22–29](</home/ribelo/projects/exergy/docs/requirements/ibkr-gateway-session.md#L22-L29>), [Gateway result fields:702–713](</home/ribelo/projects/exergy/lib/ibkr/ibkr.ml#L702-L713>), [Flex result fields:969–981](</home/ribelo/projects/exergy/lib/ibkr/ibkr.ml#L969-L981>), and [observed-result wrapper:119–130](</home/ribelo/projects/exergy/lib/facade_core/exergy_runtime.ml#L119-L130>).
- Already present, not new work: typed Error versus Ok classification, elapsed-time measurement, correlation IDs, fiber context and Redact. Existing context export has a distinct repair in the [OTel capability](<../otel/01-otel.md>).

Verified 2026-10-04: `Logger.span ?complete` (stories 9–18) by `test/observability/span_complete.ml` ("Span completion": ok/error completion, identity, timing, precedence, body defect, Eio cancellation, extractor defect, redaction, sibling/nested isolation) on the memory, journal and typed-record reporters; stories 1–8 by the existing `test/observability/run.ml` and `v1_logger.ml`, all passing.
The Door/OTLP local-collector integration named in Testing Decisions is deliberately left to the OTel slice ([OTel capability](<../otel/01-otel.md>)); no ox_otel dependency was added.
