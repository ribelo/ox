---
status: ready-for-agent
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

## Out of Scope

Exemplars, views, exponential histograms.
