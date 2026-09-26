---
status: completed
package: eta_app
consumer: Leash milestone 6 (svc-ljl3, svc-tkor), pulled by milestone 1 row L1
---

# The Door validates decoded config against the environment

## Problem Statement

`eta_schema` decodes and checks shape; it is pure and must stay so. Some config errors are only visible against the operating system — a Chrome binary that does not exist or is not executable, a profile directory that cannot be read. Leash must fail at boot on those (svc-ljl3) and `leash config check` must report them without starting (svc-tkor). Today the Door has no place to run such a check: the built-in `config check` only decodes.

## Solution

An optional validator passed to the Door, run after decoding and before the program and by `config check`, with the Env values it needs, whose failures are rendered like config errors.

## User Stories

1. As a service author, I want `Eta_app.run` and `run_for_test` to accept `?validate : 'base Env.t -> 'cfg -> (unit, validation_error list) result`, run after decoding and env overrides and before the program's switch is created, so that environment-dependent config errors stop the service before anything starts. ^napp-57qi
2. As an operator, I want `config check` to run the same validator and report every validation error with its JSON pointer and message, exit 2 on any, and print the redacted effective config only when there are none, so that checking and booting agree. ^napp-noiv
3. As a service author, I want `validation_error` to be a small record `{ pointer : string; message : string }` rendered in the same style as decode issues, so that the operator sees one kind of config error. ^napp-dnru

## Implementation Decisions

- The validator receives the Door's Env (so it takes `fs`, not ambient `Sys`); in `run_for_test` the test's env is passed.
- A validator that raises is a defect: rendered with `Cause.pp`, exit 2.
- Absent `?validate` behaves exactly as today.

## Testing Decisions

- `test/app`: validator failing blocks the program (program never entered), exit 2, stderr names pointer and message — napp-57qi, napp-dnru; `config check` with failing and passing validator — napp-noiv.

## Out of Scope

Async or long-running validation; validation after start.

Verification: `nix develop -c dune build @install`, `nix develop -c dune test`, and `nix develop -c dune build @fmt` passed for the full tree.
Verification: `test/app` ran six new story-linked cases — a failing validator exits 2 without entering the program, env overrides and the Door's Env reach it, an fs-backed check fails on a missing file, a raising validator renders through `Cause.pp`, `config check` reports the same errors before printing the redacted config, and `Eta_app.run` in the spawned fixture stops before the program on a rejected port.
