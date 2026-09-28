---
status: completed
package: eta_app
consumer: Pie migration (pienext-zyck, pienext-y5y2)
---

# The Door carries a program's own CLI and its own config source

## Problem Statement

Pie's CLI has service arguments (`--ptt-transcribe-keysym`, `--ptt-translate-keysym`) and many verbs (sources, meter, record, type, status, toggle, pause, resume, retry, msg) that need Eio capabilities. `Eta_app.run` takes prebuilt `(unit -> int) Cmd.t` commands with no Env and parses the service from `--config` alone, so those verbs would need a second Eio loop. Pie's config is `stt.toml` with required-source, bounded-read and relative-prompt rules; the Door resolves a fixed `config.toml`.

## User Stories

1. As a service author, I want to give the Door a typed `'args Cmdliner.Term.t` whose value reaches my program beside Env and config, so that service flags parse once, in the Door. ^napp-ytqk
2. As a service author, I want extra commands built by the Door with its Env and an owned switch (e.g. `?commands:('base Env.t -> sw:Eio.Switch.t -> 'cfg option -> int) Cmdliner.Cmd.t list` — decide the exact shape, including whether a command needs decoded config), under the same signal and exit boundary, so that every verb runs in the one Eio loop. ^napp-x11e
3. As a service author, I want to declare the config file name and missing-file policy (required or defaults) and a production reader (bounded, regular files only) honoured by run, `config check` and `run_for_test`, and to receive the resolved source path, so that my existing file keeps working and relative paths resolve against it. ^napp-ersz

## Implementation Decisions

- Additive: today's signatures keep working (existing consumers: Leash, grip, inn). If a clean shape needs a breaking change, record it and update Leash/grip/inn call sites in the same row.
- The program keeps live reload; the Door only loads at start and for `config check`.
- `run_with_args` and `run_for_test_with_args` accept a typed `service_args` term; `commands_with_env` receives the Door Env and `run_owned (switch -> result) -> exit code`. Extra verbs choose their own configuration policy, rather than decoding service config implicitly.
- `config_file`, `missing`, `validate_source`, `read_file` (production), and `read` (tests) select the source/read policy; `Config.read_regular ~max_bytes` supplies a bounded regular-file reader. Old Door entry points remain wrappers; no Leash, grip or inn call sites change.

## Testing Decisions

- test/app: service term reaches the program; bare invocation with overrides; an extra command using Env/switch; cancellation of a long-lived command on SIGTERM; custom file name, required-missing error, bounded read, source path passed.
- Delivered in `test/app/run.ml`: ^napp-ytqk (`test_door2_service_args`); ^napp-x11e (`test_door2_commands`, `test_door2_real_signal_extra`); ^napp-ersz (`test_door2_source_policy`, `test_door2_production_reader`, `test_door2_bounded_reader`). Full `@install`, `test`, `@fmt` gates pass using `_build_door2`.
