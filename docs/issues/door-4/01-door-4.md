---
status: ready-for-agent
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

## Implementation Decisions

- Additive on `run`, `run_with_args`, `run_for_test`, `run_for_test_with_args`; defaults preserve today's behaviour for Leash, grip, inn, Pie.

## Testing Decisions

- test/app: help shows the given doc; a decode failure and a validation failure exit `validation_exit`; with `~log_level:Warn` an info record reaches neither the journal nor a telemetry reporter, a warning reaches both.
