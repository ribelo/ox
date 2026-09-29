---
status: completed
package: eta_app
consumer: nema row 31 (U4 deviations from nema's CLI and journal contract)
---

# The Door keeps a program's help text, validation exit code and journal volume

## Problem Statement

Under the Door, `nema --help` shows the Door's "Run the service." instead of nema's own description; a configuration that fails validation exits 2 where nema documents 64; and the journal logger records every info-level span, so each HTTP request writes about three JSON lines to journald where nema used to write only errors.

## User Stories

1. As a service author, I want `?doc:string` (and `?man` if cheap) for the Door's top-level command, so that `--help` describes my program. ^napp-fsxf
2. As a service author, I want `?validation_exit:int` (default 2) for a configuration that fails decoding or validation, so that my documented code survives. ^napp-7hvu
3. As a service author, I want `?log_level:Eta_observability.Logger.level` (default Info) for the Door's journal logger (and the program logger it builds), so that a quiet service keeps journald quiet; telemetry reporters still receive what the level admits. ^napp-k9in
4. As a service author, I want the journal quieter than my telemetry, so that journald gets only errors while the OTLP exporter still receives info spans. ^napp-xb3q (consumer: nema row 31) ^napp-q2a2

## Implementation Decisions

- Additive on `run`, `run_with_args`, `run_for_test`, `run_for_test_with_args`; defaults preserve today's behaviour for Leash, grip, inn, Pie.

- ^napp-xb3q: `?journal_level:Eta_observability.Logger.level` filters only the journal reporter; absent it there is no journal-specific threshold. `?log_level` still controls the program logger and every telemetry reporter.

## Testing Decisions

- test/app: help shows the given doc; a decode failure and a validation failure exit `validation_exit`; with `~log_level:Warn` an info record reaches neither the journal nor a telemetry reporter, a warning reaches both.
- ^napp-xb3q: `?journal_level` defaults to no additional filter and wraps only the journal reporter (including the pre-config logger). test/app checks info spans reach telemetry but not an Error-only journal, an error reaches both, and default delivery remains unchanged; test/observability checks the reporter filter on its own.

Verified: test/app covers ^napp-fsxf ^napp-7hvu ^napp-k9in, including `config check` and the validator-defect boundary.
The isolated `@install`, full `dune test`, and `@fmt` gates passed with `DUNE_BUILD_DIR=_build_door4`.
Verified ^napp-xb3q: test/app and test/observability passed with the three isolated gates using `DUNE_BUILD_DIR=_build_jl`.
