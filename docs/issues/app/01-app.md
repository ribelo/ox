---
status: completed
package: eta_app
consumer: Leash milestone 1 (chrome-fuao, chrome-b288, chrome-fwnu) and milestone 6 (svc-dit8, svc-ljl3, svc-kzt6, svc-p67t, svc-gxhu, svc-tkor)
---

# App: the Door, the Service shape, and config

## Problem Statement

Every service needs the same twenty things at its edge — build the Eio environment, decode config, install SIGINT/SIGTERM as a clean stop, run the program, print why it died, return an exit code — and every service that writes them itself writes them differently. Pie discovered this by deleting a component runtime and converging on an explicit ordered-resource shape; eta-next makes that shape the only one.

## Solution

`eta_app`: `Eta_app.run`, the Door; `Eta_app.SERVICE`, the module type every Service implements; `Status`; `Eta_app.serve`, which blocks until stop and answers status; and config decoding through `eta_schema` with declared environment overrides.

## User Stories

1. As a service author, I want `Eta_app.run ~name ~config program` to run `Eio_main`, build Env, decode config, run `program env config` inside a root Switch, and return the process exit code, so that main is one line. ^napp-3j07
2. As an operator, I want SIGINT and SIGTERM to cancel the program as an interruption, let every Switch release its resources in reverse order, and exit 0 (not 130) when the stop was clean, so that systemd sees a clean stop. ^napp-78pf
3. As an operator, I want a typed failure to print its `pp_err` rendering and exit 1, and a defect or composite Cause to print the full `Cause.pp` rendering and exit 2, so that a crash never leaves an empty journal. ^napp-f7d6
4. As a service author, I want `SERVICE` to be `type t`, `type config`, `type deps`, `type error`, `create : sw:Switch.t -> config -> deps -> (t, error) result`, `status : t -> Status.t`, so that every long-lived part of a service has one shape. ^napp-qg7n
5. As a service author, I want `Status.t` to be a small structured value (name, state as `Ok | Degraded of string | Failed of string`, and key-value details), so that status is comparable across services. ^napp-pn0a
6. As a service author, I want `Eta_app.serve ~sw statuses` to block until the program is interrupted and, while blocked, answer a status query function composed from the given thunks, so that the process stays up and reports truthfully. ^napp-kq3b
7. As an operator, I want config read from a TOML file whose path comes from `--config` or `$XDG_CONFIG_HOME/<name>/config.toml`, decoded through an `eta_schema` schema, so that config is validated before anything starts. ^napp-2aa6
8. As an operator, I want unknown keys, missing required keys and wrong types reported with a JSON-pointer location and the process to exit 2 without starting, so that misconfiguration is obvious. ^napp-yplu
9. As an operator, I want the schema to declare which fields an environment variable may override (`OPENROUTER_API_KEY` over `[models].api_key`), applied after the file, so that secrets never need to be in a file. ^napp-tuvw
10. As an operator, I want `<name> config check [--config path]` to validate and print the effective config with secrets redacted, exit 0/2, so that I can edit safely. ^napp-svkp
11. As a service author, I want Env to be Eio's `Eio_unix.Stdenv.base` plus the logger the Door created, passed to the program, so that programs take real capabilities and tests pass mocks. ^napp-o6d6
12. As a service author, I want the Door to create the journal logger (`eta_observability`) with the service name and hand it in Env, so that logging is configured once. ^napp-mbpr
13. As a test author, I want `Eta_app.run_for_test` (or the Door's internals exposed as functions taking an Env) so that a whole program runs in-process under `Eio_mock` without signals or a real config file. ^napp-433c
14. As a kernel maintainer, I want `eta_app` to depend only on `eta`, `eta_schema`, `eta_observability`, `eio`, `eio_main`, `cmdliner` and `toml`, so that the Door is small. ^napp-fu4q

## Implementation Decisions

- Exit codes: 0 clean or interrupted, 1 typed failure, 2 defect/composite/config error. (Differs from v1's 130 on purpose: SIGTERM is the normal way a service stops.)
- Signal handling: `Eio_unix` signal → cancel the root Switch with an `Interrupt_id` named "signal"; `Scope.run` at the root classifies it; the Door treats `Interrupt (Some signal_id)` as clean.
- The program's Switch is the root Switch; Services acquire against it; `serve` awaits a Promise resolved by the signal handler.
- Config pipeline: file → TOML (`toml` opam) → JSON (`eta_json`) → `eta_schema` decode → env overrides declared in the schema → typed record. Secrets are fields marked in the schema; `config check` prints them as `<redacted>`.
- Cmdliner provides `run`, `config check`, `--config`; a consumer may add subcommands through a hook.
- Status is a value; `serve` composes thunks so status is read at query time.

## Testing Decisions

- Tests under `test/app/`: run the Door in-process with a fake config file and a fake program; assert exit codes, stderr content, and release order via a recording Switch — napp-3j07, napp-78pf, napp-f7d6, napp-433c.
- Config tests are table-driven over files and env — napp-2aa6, napp-yplu, napp-tuvw, napp-svkp.
- A two-Service program with a fake dep proves the SERVICE shape composes — napp-qg7n, napp-pn0a, napp-kq3b.

## Out of Scope

A control socket (separate spec `ipc`), hot reload, daemonization, metrics export.

Verification: `nix develop -c dune build @install` and `nix develop -c dune test` passed for the full tree.
Verification: `nix develop -c dune test test/app` passed ten story-linked Door, Service, config, status, CLI, and interruption tests.

## Further Notes

The systemd unit for a consumer sets nothing special: exit 0 on stop is the point of napp-78pf.
