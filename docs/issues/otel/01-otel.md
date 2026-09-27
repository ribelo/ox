---
status: completed
package: eta_otel (eta, eta_json, eta_http, eta_observability, eio; alcotest/eio_main for tests)
consumer: nema (bin/nema/telemetry.ml, bin/nema/main.ml)
---

# Scoped OTLP logs and traces for nema

## Problem Statement

Nema initializes a caller-scoped OTLP exporter, sends logs and spans through it, and explicitly settles telemetry before releasing its HTTP client. eta-next has structured Logger records and span start/end events, but no exporter. The v1 exporter is tied to the removed effect runtime and also exports metrics, which this migration row defers.

## Solution

Add `eta_otel` with a pure OTLP/JSON logs and traces encoder adapted from `v1:lib/otel/otlp_json.ml` and a caller-scoped Eio worker. The worker batches records by signal, has bounded admission with counted drops, posts through the borrowed eta_http client, and settles admitted work during explicit shutdown before switch release. An eta_observability Logger reporter feeds logs and converts completed Logger.span events into OTLP spans; eta_observability never depends on eta_otel. Preserve typed HTTP/status failures without logging collector response bodies.

## User Stories

1. As nema's service author, I want an OTLP reporter for Logger records and completed Logger spans with inherited context, so service logs and span outcomes go to their respective OTLP endpoints without a second tracing API. ^notel-6m2q
2. As nema's service author, I want a caller-scoped exporter over a borrowed eta_http client, endpoint and resource identity, so shutdown drains telemetry before nema releases its HTTP client. ^notel-j9vc
3. As an operator, I want bounded queues, signal-specific batches, drop counts, and explicit flush/shutdown settlement, so overload uses finite memory and admitted records are not silently abandoned on normal shutdown. ^notel-p4xe
4. As a kernel maintainer, I want v1's pure OTLP/JSON resource/scope/span/log wire encoding and regression assertions adapted to the new Logger record types, so numeric timestamps, severity and attributes remain valid OTLP without copying the effect runtime. ^notel-z7dk
5. As nema's service author, I want typed transport/status failures and a shutdown result that distinguishes a failed or timed-out drain, so telemetry failures are actionable without exposing response bodies or swallowing cancellation. ^notel-t8br

## Implementation Decisions

- Use v1 `otlp_json.ml` as the pure encoding source; remove metric-only and removed `Eta.Capabilities` record shapes, preserve resource/scope envelopes, integer-string nanoseconds and OTLP field names. Copy relevant encoder assertions from v1 tests into offline tests.
- The exporter owns its worker fiber on the caller's Switch and borrows the supplied eta_http.Client.t. No process-global SDK or runtime, no telemetry of its own HTTP sends (avoid recursive export).
- The logger binds generated trace/span IDs in fiber context around the existing start/body/end records. The reporter suppresses span starts and converts completed end records into spans, reconstructing start time from their elapsed milliseconds; incomplete spans are never exported. Logs preserve inherited context and redacted field representations. Nema passes `~span_ids:(Eta_otel.span_ids exporter)` when creating the logger. IDs use a non-cryptographic generator and are correlation IDs, not secrets. `Logger.span` accepts a global callback because binding through `Context.with_fields` and `Eio.Fiber.with_binding` requires one (nmodes-8t8v, nmodes-8y46).
- A full queue drops newest records and increments a counter; accepted records stay owned until sent or reported failed. Shutdown seals admission and waits for work; a timeout is a typed failure rather than a successful drain.

## Testing Decisions

- Tests under `test/otel/` cite each story ID, compare parsed OTLP JSON envelopes with v1 fixtures/shape assertions, and use a local HTTP server for POST paths, batching, collector refusal, bounded admission, flush and shutdown. No network access to a live collector.

## Verification

Scoped `eta_otel` build and offline tests pass (5 OTel tests; 25 observability tests). The owned OCaml files pass `ocamlformat --check`. Full-tree gates are delegated to the integration lead while sibling rows are in progress; the first `@install` attempt failed on the concurrent `eta_sql_driver` stub, and `@fmt` flagged concurrent HTTP service edits before the owned OTel files were formatted.

## Out of Scope

Metrics and self-metrics, threaded bootstrap, the old runtime/capability interfaces, trace propagation headers, retry policy, live external collector tests.
