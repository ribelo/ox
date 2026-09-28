---
status: ready-for-agent
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

## Testing Decisions

- test/app: service term reaches the program; bare invocation with overrides; an extra command using Env/switch; cancellation of a long-lived command on SIGTERM; custom file name, required-missing error, bounded read, source path passed.
