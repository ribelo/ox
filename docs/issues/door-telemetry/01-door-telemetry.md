---
status: ready-for-agent
package: eta_app, eta_observability, eta_otel
consumer: Leash milestone 6 row L25 (OTLP export by config), and every later consumer that exports telemetry (nema)
---

# The Door can export telemetry that the program configures

## Problem Statement

A program cannot add an exporter to the logger the Door creates: `Eta_app.run` builds the journal logger itself and offers no hook, and `Eta_otel.create` has no way to send the headers an OTLP collector commonly requires (an API key, a tenant). Leash's L25 wants OTLP export enabled from its config; without these two pieces it would have to rebuild the Door's logging itself.

## Solution

A reporter hook on the Door, a tee reporter, and optional headers on the exporter.

## User Stories

1. As a service author, I want `Eta_app.run` and `run_for_test` to accept `?telemetry:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> Eta_observability.Logger.Reporter.t list)`, called after config is decoded and validated, whose reporters receive every record alongside the journal, and whose resources live on the root switch (so an exporter flushes before the Door returns), so that export is configured from the program's own config. ^napp-idii
2. As a service author, I want `Eta_observability.Logger.Reporter.tee : t list -> t`, delivering each record to every reporter in order, a failing one never preventing the others, so that the journal and an exporter coexist. ^nobs-8i5y
3. As an operator, I want `Eta_otel.create ?headers:(string * string) list` sent on every export request (values never logged; a header value may be an `Eta_observability.Redact.t` or treated as secret), so that a collector requiring an API key works. ^notel-6o5v

## Implementation Decisions

- Additive only; absent `?telemetry` and `?headers` behave exactly as today.
- When span ids are needed for export, the telemetry hook may also return the generator; if `Logger.create ?span_ids` must be passed by the Door, add `?span_ids` to the hook's result rather than a second hook — decide at implementation and record it.

## Testing Decisions

- `test/app`: a telemetry reporter receives records; its resource on the root switch flushes before exit on SIGTERM-path (reuse the real-signal fixture) — napp-idii. `test/observability`: tee order and isolation — nobs-8i5y. `test/otel`: headers on the wire, absent from logs — notel-6o5v.

## Out of Scope

Metrics; config parsing for telemetry (the program's own config).
