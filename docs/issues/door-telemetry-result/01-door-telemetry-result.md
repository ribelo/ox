---
status: ready-for-agent
package: eta_app
consumer: nema row 31 (nemanext-ro0v)
---

# Telemetry acquisition can fail as an ordinary startup error

## Problem Statement

The Door's `?telemetry` hook returns a plain value and treats a raise as a defect, but acquiring an OTLP exporter can fail (bad endpoint, refused config). nema reports that as a classified startup failure; inside the program it's too late, because the Door has already built the logger that should carry the exporter's reporter and span ids.

## User Stories

1. As a service author, I want the telemetry hook to return `(Eta_app.telemetry, 'err) result`, an `Error` rendered through the Door's `pp_err` and exit path before the program logger exists, so that exporter initialization errors are ordinary startup failures, not defects. Existing hooks keep working (additive, or update Leash/Pie/grip/inn call sites in the same row). ^napp-scz2

## Testing Decisions

- test/app: an `Error` from the hook exits as a typed failure with its message and never enters the program; `Ok` behaves as today.
