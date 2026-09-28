---
status: completed
package: eta_app
consumer: Leash milestone 1 (chrome-fuao, chrome-b288, chrome-fwnu) and milestone 6 (svc-dit8, svc-ljl3, svc-kzt6, svc-p67t, svc-gxhu, svc-tkor, svc-x8rp), and L31 (run-9ypy)
---

# App: the Door, the Service shape, and config

## Problem Statement

Every service needs the same twenty things at its edge — build the Eio environment, decode config, install SIGINT/SIGTERM as a clean stop, run the program, print why it died, return an exit code — and every service that writes them itself writes them differently. Pie discovered this by deleting a component runtime and converging on an explicit ordered-resource shape; eta-next makes that shape the only one.

## Solution

`eta_app`: `Eta_app.run`, the Door; `Eta_app.SERVICE`, the module type every Service implements; `Status`; `Eta_app.status_query`, which composes status thunks into one query, and `Eta_app.serve`, which blocks until stop; and config decoding through the config type's derived `of_yojson` plus the consumer's environment function, with the TOML-to-JSON step unchanged inside the Door (ADR-0008; the schema DSL is gone with `docs/issues/remove-eta-schema/01-remove-eta-schema.md`).

## User Stories

1. As a service author, I want `Eta_app.run ~name ~config program` to run `Eio_main`, build Env, decode config, run `program env config` inside a root Switch, and return the process exit code, so that main is one line. ^napp-3j07
2. As an operator, I want SIGINT and SIGTERM to cancel the program as an interruption, let every Switch release its resources in reverse order, and exit 0 (not 130) when the stop was clean, so that systemd sees a clean stop. ^napp-78pf
3. As an operator, I want a typed failure to print its `pp_err` rendering and exit 1, and a defect or composite Cause to print the full `Cause.pp` rendering and exit 2, so that a crash never leaves an empty journal. ^napp-f7d6
4. As a service author, I want `SERVICE` to be `type t`, `type config`, `type deps`, `type error`, `create : sw:Switch.t -> config -> deps -> (t, error) result`, `status : t -> Status.t`, so that every long-lived part of a service has one shape. ^napp-qg7n
5. As a service author, I want `Status.t` to be a small structured value (name, state as `Ok | Degraded of string | Failed of string`, and key-value details), so that status is comparable across services. ^napp-pn0a
6. As a service author, I want `Eta_app.status_query : (unit -> Status.t) list -> (unit -> Status.t list)` to compose status thunks as a plain value, and `Eta_app.serve ~sw ()` to only block until the program is interrupted, so that a Service created before serving can hold the query and the process stays up and reports truthfully. ^napp-kq3b
7. As an operator, I want config read from a TOML file whose path comes from `--config` or `$XDG_CONFIG_HOME/<name>/config.toml`, so that config is validated before anything starts. The file format and its path are unchanged (^nnoschema-boxo); its schema-decoding half is superseded by ^nnoschema-5mdj, which decodes with the config type's derived `of_yojson`. ^napp-2aa6
8. As an operator, I want a missing required key, a wrong-typed value or a key the config type does not name reported with the field's path and the process to exit 2 without starting, so that misconfiguration is obvious. ^nnoschema-zi2m keeps this rule and changes only its rendering: the deriver reports a dotted path and the offending subtree (or the unknown key) instead of a JSON pointer. ^napp-yplu
9. As an operator, I want an explicit environment function to override fields of the decoded config (`OPENROUTER_API_KEY` over `[models].api_key`), so that secrets never need to be in a file. Superseded by ^nnoschema-5mdj: overrides are plain code applied to the decoded value, so a field only the environment supplies is an `option` or carries `[@default]`. ^napp-tuvw
10. As an operator, I want `<name> config check [--config path]` to validate and print the effective config with secrets redacted, exit 0/2, so that I can edit safely. Superseded by ^nnoschema-36cj (it prints the derived `yojson_of_t` after environment overrides) and ^nnoschema-ifg0 (a secret is `Redact.t`, so it is redacted by type). ^napp-svkp
11. As a service author, I want Env to be Eio's `Eio_unix.Stdenv.base` plus the logger the Door created, passed to the program, so that programs take real capabilities and tests pass mocks. ^napp-o6d6
12. As a service author, I want the Door to create the journal logger (`eta_observability`) with the service name and hand it in Env, so that logging is configured once. ^napp-mbpr
13. As a test author, I want `Eta_app.run_for_test` (or the Door's internals exposed as functions taking an Env) so that a whole program runs in-process under `Eio_mock` without signals or a real config file. ^napp-433c
14. As a kernel maintainer, I want `eta_app` to depend only on `eta`, `eta_observability`, `eio`, `eio_main`, `cmdliner`, `toml` and `yojson` — the last admitted by ADR-0007 for the Door's config codecs — so that the Door is small. Supersedes ^napp-fu4q. ^napp-deps
15. As an operator, I want the service to start with its defaults when no config file exists at the default path, while a `--config` path that does not exist is still an error, so that a fresh install needs no file. ^napp-9x0s
16. As a service author, I want to name the Door's start command, so that a program can use `run` for its own verb. ^napp-d5e4

The validator half of the Door is its own spec, `docs/issues/door-validate/01-door-validate.md` (^napp-57qi, ^napp-noiv, ^napp-dnru): `?validate` keeps the signature it was delivered with.

## Implementation Decisions

- Exit codes: 0 clean or interrupted, 1 typed failure, 2 defect/composite/config error. (Differs from v1's 130 on purpose: SIGTERM is the normal way a service stops.)
- Signal handling: `Eio_unix` signal → cancel the root Switch with an `Interrupt_id` named "signal"; `Scope.run` at the root classifies it; the Door treats `Interrupt (Some signal_id)` as clean.
- The program's Switch is the root Switch; Services acquire against it; `serve` blocks in `Eio.Fiber.await_cancel`, so the Door's signal monitor ends the program by cancelling that switch.
- Config pipeline (^nnoschema-boxo, ^nnoschema-5mdj): file → TOML (`toml` opam) → `Yojson.Safe.t` in `eta_app` → the consumer's derived `of_yojson` → the consumer's `env ~getenv` overrides → `?validate` → the program. A decode failure is the deriver's message, which names the dotted path and carries the offending subtree (bounded); TOML dates and non-finite floats are refused with the JSON pointer of the value.
- The config the Door takes is `'cfg Eta_app.Config.t` (`of_yojson`, `yojson_of_t`, `env`): a plain type with `[@@deriving yojson]` is the schema (ADR-0008). `config check` prints `yojson_of_t` of the effective config after the overrides and only when the validator accepts.
- An absent config file is an error only where the operator named it. `Config.resolve` says which path came from where — `` `Explicit` `` for `--config`, `` `Default` `` for the path resolved from the service name — and `Config.load` decodes the empty document for a `` `Default` `` that is `` `Missing` ``, so a config type whose fields all carry defaults starts with no file. The read outcome separates `` `Missing` `` from `` `Unreadable` ``, so a file that is there and cannot be read stays an error at either path, and `config check` loads through the same function, which is why it follows the same rule. ^napp-9x0s
- Cmdliner provides the start command, `config check`, `--config`; a consumer may add subcommands through a hook. The start command's name is `?service_command`, `"run"` unless the service author says otherwise, and the same term is the group's default, so a bare invocation starts the program under any name. A program that wants `run` for a verb of its own names the Door's command something else and adds that verb through `?commands`; the name must then be free there, since Cmdliner refuses two subcommands with one name. ^napp-d5e4
- Status is a value; `Eta_app.status_query` composes the thunks into one query, so status is read at call time and a Service can hold the query before `serve` blocks.

## Testing Decisions

- Tests under `test/app/`: run the Door in-process with a fake config file and a fake program; assert exit codes, stderr content, and release order via a recording Switch — napp-3j07, napp-78pf, napp-f7d6, napp-433c.
- Config tests are table-driven over files and env — napp-2aa6, ^nnoschema-zi2m, ^nnoschema-5mdj.
- An unknown config key is refused at boot by the derived decoder, which names the path and the key — ^napp-yplu, ^nnoschema-zi2m (Leash svc-ljl3).
- The derived config's round-trip, a decode failure's path and subtree, the environment override, and redaction in `config check` — ^nnoschema-5mdj, ^nnoschema-zi2m, ^nnoschema-ifg0, ^nnoschema-36cj, ^nnoschema-boxo.
- An absent config file is table-driven over the two sources and both subcommands: a missing default path starts a program whose config type has defaults and prints them from `config check`, a missing `--config` exits 2 naming the path, an unreadable file exits 2 either way, and a type without defaults still refuses the empty document. The fixture — the only executable that goes through `Eta_app.run` — runs with `XDG_CONFIG_HOME` set to a directory that is not there, so the real read's classification of Eio's `Not_found` is covered too — ^napp-9x0s.
- A two-Service program with a fake dep proves the SERVICE shape composes, and its Services take the derived config type — napp-qg7n, napp-pn0a, napp-kq3b, ^nnoschema-p7fv.
- The name of the Door's start command is tested through `run_for_test`: the default `run` and a custom `serve` each start the program, a bare invocation starts it under either name, the name a renamed Door no longer uses is refused with the program never entered, and a consumer command named `run` is dispatched beside `service_command:"serve"` — ^napp-d5e4 (Leash L31 run-9ypy). The signal fixture, the one executable that goes through `Eta_app.run`, names its start command `serve`, so an explicit `serve` proves the Door forwards the name while its bare spawns prove the default term still starts the program.

## Out of Scope

A control socket (separate spec `ipc`), hot reload, daemonization, metrics export; JSON Schema generation for AI tool definitions (its own row when the AI package is pulled).

## Further Notes

The systemd unit for a consumer sets nothing special: exit 0 on stop is the point of napp-78pf.

Story ^napp-kq3b's `serve ~publish` shape is superseded by `docs/issues/review-fixes-1/01-review-fixes-1.md` (^nfix-j678): the query is composed by `Eta_app.status_query` as a plain value and `serve ~sw ()` only blocks until interrupted.

## Verification

`nix develop -c dune build @install`, `dune test` and `dune build @fmt` passed for the whole tree after row 16 (`^nnoschema-ttb5`) deleted the schema packages, and again with story 15 `^napp-9x0s` (Leash L24) landed.
`dune test test/app` runs 30 cases green, every case named for its story IDs: the derived config round-trip and environment override, the deriver's decode failure (missing field, wrong type, nested path, unknown key — each exit 2 with the program never entered), redaction in `config check`, the retained Door, Service, status, CLI and real-signal cases, and row 14's four validator cases, which are unchanged.
`^napp-9x0s` adds two of those cases: the absent-config table over both sources and both subcommands — a missing default file starts a program whose config type has defaults and `config check` prints them, a missing `--config` exits 2 naming the path, an unreadable file exits 2, and a type without defaults still refuses the empty document — and the fixture invocation that runs with `XDG_CONFIG_HOME` pointing at a directory that is not there, which is what proves the real `Eta_app.run` reads Eio's `Not_found` as absence.

Story 16 `^napp-d5e4` (Leash L31 run-9ypy) adds two of those cases — the Door's start command name, and a consumer `run` beside `service_command:"serve"` — and renames the start command the signal fixture asks for: the fixture's explicit `serve` is what proves the real `Eta_app.run` forwards `?service_command`.
