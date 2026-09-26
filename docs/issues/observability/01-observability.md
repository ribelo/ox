---
status: completed
package: eta_observability
consumer: Leash milestone 1 (chrome-fuao), milestone 6 (svc-p67t, svc-qilu, svc-f4op)
---

# Observability: structured logging first, tracing as context

## Problem Statement

A service needs structured logs in the journal with the fields that identify the work (service name, tab handle, owner, command), a way to attach those fields to everything a fiber does without threading them, and a redaction rule so secrets and page content never reach a log line. OTLP export can come later; the shape must allow it.

## Solution

`eta_observability`: `Logger` (levels, structured records, a journal reporter writing one JSON object per line to stderr, an in-memory reporter for tests), `Context` (fiber-local key-value fields that every record inherits, crossing `Fiber.fork`), and `Redact` (a wrapper type whose printer never shows the value).

## User Stories

1. As a service author, I want `Logger.log logger level ~msg ?fields ()` producing a record with timestamp, level, message, fields and the fiber's inherited context, so that every line is structured. ^nobs-og4h
2. As a service author, I want `Context.with_fields [("tab", …); ("owner", …)] f` to attach fields to everything logged inside `f`, including in fibers forked inside, so that identity is not threaded by hand. ^nobs-2d4r
3. As an operator, I want the journal reporter to write one compact JSON object per line to stderr with a stable key order, so that `journalctl` output is greppable and parseable. ^nobs-ek28
4. As a test author, I want an in-memory reporter with a query by level and field, so that tests assert what was logged and what was not. ^nobs-rayu
5. As a service author, I want `Redact.t` values to print as `<redacted>` through every path (`pp`, JSON, string), so that a secret cannot leak by accident. ^nobs-iedi
6. As a service author, I want a per-logger minimum level and a rate limit for a named repeated message, so that a flapping component cannot flood the journal. ^nobs-262i
7. As a service author, I want `Logger.span name f` to log start and end with elapsed time and an outcome (ok, failed with cause summary), so that tracing exists as structured logs before any exporter. ^nobs-xovg
8. As a kernel maintainer, I want the package to depend on `eta`, `eio` and `eta_json` only, so that OTLP export is a later, separate package. ^nobs-6x58

## Implementation Decisions

- Context is `Eio.Fiber.create_key` + `Fiber.with_binding`; a forked fiber inherits bindings in Eio, which is the whole reason this is not an effect.
- Records carry `Cause` summaries through `Cause.pp_compact`, never page or request bodies; the redaction rule is by type (`Redact.t`), not by field name.
- Timestamps from the Door's clock (wall clock for the journal), monotonic elapsed for spans.

## Testing Decisions

- `test/observability/` with the in-memory reporter: inheritance across fork, redaction through each printer, rate limit with a mock clock, span outcome on Ok/Error/raise — all stories.

## Out of Scope

OTLP, metrics, sampling, trace propagation headers — each a later spec when Leash milestone 6 or Pie pulls it.

Verification: `nix develop -c env DUNE_BUILD_DIR=_build_obs dune build @install` passed for the whole tree and `dune test test/observability` passed 20 tests; every story ID (^nobs-og4h, ^nobs-2d4r, ^nobs-ek28, ^nobs-rayu, ^nobs-iedi, ^nobs-262i, ^nobs-xovg, ^nobs-6x58) is cited by name in `test/observability/run.ml`.
Verification: eta_test's mock clocks drive the wall-clock timestamp (asserted byte-for-byte in the journal line), the rate-limit window, and span elapsed time; context inheritance across `Eio.Fiber.fork`, redaction through `pp`/`to_string`/JSON/record, and span outcomes on Ok, typed Error, raise and cancellation are all asserted.
