---
status: completed
package: eta_app, eta_observability, eta_otel
consumer: Leash milestone 6 row L25 (OTLP export by config) and L24 (config init, svc-x8rp), grip row 29 (OTLP resource attributes), and every later consumer that exports telemetry (nema)
---

# The Door can export telemetry that the program configures

## Problem Statement

A program cannot add an exporter to the logger the Door creates: `Eta_app.run` builds the journal logger itself and offers no hook, and `Eta_otel.create` has no way to send the headers an OTLP collector commonly requires (an API key, a tenant). Leash's L25 wants OTLP export enabled from its config; without these two pieces it would have to rebuild the Door's logging itself.

## Solution

A reporter hook on the Door, a tee reporter, optional headers and resource attributes on
the exporter, and consumer subcommands in the Door's own `config` group.

## User Stories

1. As a service author, I want `Eta_app.run` and `run_for_test` to accept `?telemetry:(sw:Eio.Switch.t -> 'base Env.t -> 'cfg -> Eta_app.telemetry)`, called after config is decoded and validated, whose `reporters` receive every record alongside the journal and whose `span_ids` is the program logger's generator (see the span-ids decision below), and whose resources live on the root switch (so an exporter flushes before the Door returns), so that export is configured from the program's own config. ^napp-idii
2. As a service author, I want `Eta_observability.Logger.Reporter.tee : t list -> t`, delivering each record to every reporter in order, a failing one never preventing the others, so that the journal and an exporter coexist. ^nobs-8i5y
3. As an operator, I want `Eta_otel.create ?headers:(string * string) list` sent on every export request (values never logged; a header value may be an `Eta_observability.Redact.t` or treated as secret), so that a collector requiring an API key works. ^notel-6o5v
4. As an operator, I want resource attributes such as service.version on every export, so that telemetry from different builds is distinguishable. ^notel-jzdm
5. As a service author, I want to add subcommands to the Door's config group, so that `<name> config init` sits beside `config check`. ^napp-wf22

## Implementation Decisions

- Additive only; absent `?telemetry`, `?headers`, `?resource` and `?config_commands` behave exactly as today.
- **Span ids (decided).** The hook's result is the record `Eta_app.telemetry = { reporters : Reporter.t list; span_ids : (unit -> string) option }`, not a bare reporter list: the Door passes both to the program logger's `Logger.create`, so a hook needs one result, not a second hook. The hook itself receives the `Env` the validator saw, whose logger writes to the journal alone, because the program's logger cannot exist before the hook's result does; the Door therefore creates the validation logger and, on the run path with telemetry configured, the program's logger (a `Reporter.tee` of the journal and the hook's reporters, with the hook's generator). Without a hook, exactly one logger is created, as before.
- `Eta_otel.create ?resource` appends its attributes after the exporter's own `service.name`; a caller-supplied `service.name` is ignored rather than sent as a second, contradictory resource identity.
- The Door keeps its `config` group and appends `?config_commands` to it beside `check`; Cmdliner refuses a second group with that name, so the group must stay the Door's.

## Testing Decisions

- `test/app`: a telemetry reporter receives records; the hook's span ids are the program logger's; `config check` calls no hook; a raising hook is a defect; its resource on the root switch flushes before exit on the SIGTERM path (the real-signal fixture, which switches telemetry on from its own config and reads the record and the flush marker from stdout) — napp-idii. A consumer `config` subcommand runs and appears in `config --help` — napp-wf22.
- `test/observability`: tee order and isolation, and cancellation still propagating — nobs-8i5y.
- `test/otel`: headers and resource attributes on the wire for logs and traces, the secret absent from request bodies and from error renderings — notel-6o5v notel-jzdm.

## Verification

`dune build @install`, `dune test` and `dune build @fmt` are green: eta_observability 27 tests, eta_otel 7, eta_app 24. The SIGTERM test runs the real `Eta_app.run` fixture as a child, sends SIGTERM, and reads the program's record and the hook's flush marker from its stdout in that order before the process exits; the OTLP test reads the headers from a local collector's request lines and the resource attributes from the decoded `resourceLogs`/`resourceSpans` bodies.

## Out of Scope

Metrics; config parsing for telemetry (the program's own config).
