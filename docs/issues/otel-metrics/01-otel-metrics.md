---
status: completed
package: eta_otel
consumer: inn (row 30: its Eta instrumentation guide showed a metrics example; inn ingests metrics but Eta apps cannot send them), nema (row 31, if its OTel use includes metrics — confirm at its migration)
---

# OTLP metrics: instruments and an exporter

## Problem Statement

`eta_otel` exports logs and traces only. inn's instrumentation guide, written against v1, showed an Eta application recording metrics that reach inn's `POST /v1/metrics`; after inn's migration (row 30) the guide had to drop that example.

## Solution

Direct-style metric instruments on a meter, and an OTLP/HTTP JSON metrics exporter sharing `eta_otel`'s transport, resource and lifecycle.

## User Stories

1. As a service author, I want counter, up-down counter and histogram instruments with attributes, recorded in direct style from any fiber, so that my measurements have one API. ^notel-bez2
2. As an operator, I want recorded metrics exported periodically and on switch release to an OTLP/HTTP JSON metrics endpoint with the exporter's resource attributes, a bounded queue, and typed export errors on flush/shutdown, so that metrics reach a collector alongside spans and logs. ^notel-8ixo

## Implementation Decisions

- Copy v1's pure OTLP metrics JSON encoding (`v1:lib/otel`, Metric_aggregation) where it has no Effect.t; the aggregation state is per exporter, single-domain.
- Same lifecycle as the logs/traces exporter (drain on switch release, notel-1stb).

## Testing Decisions

- Local collector: counter/histogram values and resource attributes on the wire; drain on release.

## Verification

`Eta_otel.Meter` gives a program a counter, an up-down counter and a histogram, each
carrying its name, unit, description and attributes; the exporter owns one aggregation
table per exporter (single domain, no lock), posts the window on `metrics_interval`, on
`flush`, on `shutdown` and from its release hook, and shares the logs/traces transport,
resource attributes, headers, `request_deadline` and ending. `test/otel` runs 19 tests,
9 of them metrics: the pure `resourceMetrics`/`scopeMetrics` envelope with delta sums,
bucket counts of bounds+1, decimal-string integers and saturated timestamps copied from
v1's assertions; the instruments' points and bound validation; counter, up-down counter
and histogram values, attributes, resource attributes and collector headers on a local
`POST /v1/metrics`; the window exported by the switch's release; the interval posting it;
a worker busy with logs still posting it; a drained window not reposted by a second
flush; the series bound dropping and counting; and a refused window reported as
`` `Status 503 `` by `flush`.

`dune build @install`, `dune test` (23 suites, 468 tests, 0 failures) and `dune build @fmt` are
green on the whole tree. Disabling the worker's deadline check makes `a busy worker still
exports the window` fail in 0.3 s, so the regression the check exists for is covered
rather than assumed. Bounded admission for this row is a series ceiling
(`max_metric_series`, counted by `dropped`) instead of one queue slot per measurement:
measurements aggregate as they are recorded, so a full log or trace queue never costs
one, and attribute cardinality a program does not control stays finite.

## Out of Scope

Exemplars, views, exponential histograms.
