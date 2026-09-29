---
status: ready-for-agent
package: eta_otel
consumer: nema row 31 (export diagnostics used to name the OTLP signal)
---

# An export failure says which signal failed

## Problem Statement

`Eta_otel.create ?on_error` reports an export failure without saying whether logs, traces or metrics failed, so nema's export diagnostic lost its `signal` field (it now writes `"exporter"`).

## User Stories

1. As an operator, I want `on_error` to carry the signal that failed (`Logs | Traces | Metrics`) beside the error, so that an export diagnostic says which pipeline is broken. ^notel-na2w

## Implementation Decisions

- Prefer an additive shape (e.g. a new `?on_signal_error:(signal -> error -> unit)`, or a new record) so Leash, grip, inn and Pie keep compiling; if `on_error`'s type changes, update their call sites in the same row.

## Testing Decisions

- Local collector refusing only /v1/traces: the hook names Traces; logs still export.
