---
status: completed
package: ox_app
consumer: Leash L41 (milestone 10, daily use)
---

# The Door lets a consumer render every diagnostic and orient first contact

## Problem Statement

Leash's daily-use contract requires every CLI failure to be one JSON record on stderr, grouped help advertising its real exit codes, and a short orientation on a bare invocation. The Door writes Cmdliner usage text, configuration diagnostics and Cause reports itself; Leash cannot render those consistently from its commands. The Door also owns the top-level, service and configuration command information and the default term.

Pulling stories: Leash `docs/issues/daily-use/01-daily-use.md`, row L41: ^daily-azxe ^daily-6pde ^daily-3bwr ^daily-iisr ^daily-u1k2 ^daily-9396 ^daily-k9cs.

## User Stories

1. As a CLI author, I want `?diagnostic:(kind:[ `Usage | `Config | `Validation | `Defect ] -> message:string -> string)` to receive each complete Cmdliner diagnostic once before stderr is written, so that an invalid invocation produces one JSON error record, not a mixture of JSON and usage text. ^napp-5u8d
2. As a CLI author, I want the same hook to receive configuration load/decode errors as `Config` and the complete list of validator rejections as `Validation`, on both startup and `config check`, so that setup failures use my error record too. ^napp-5c2v
3. As a CLI author, I want the same hook to receive a complete Cause report as `Defect` and a plain typed program failure as `Validation`, including owned commands and telemetry or validator defects, so that the Door never leaks unwrapped failure text when I supply a renderer. ^napp-5d7f
4. As a CLI author, I want `?man:Cmdliner.Manpage.block list` and `?exits:Cmdliner.Cmd.Exit.info list` on the top-level command and the service, config and check commands the Door builds, so that I can group help and advertise the exits my CLI really returns instead of Cmdliner's defaults. ^napp-5h4m
5. As a CLI author, I want `?bare` to accept `Command of (Env.t -> (unit -> int) Cmdliner.Term.t)` alongside `Service` and `Help`, so that the first invocation can run a short orientation term built with the Door's pre-config Env without starting the service or loading config. ^napp-5b9o

6. As a CLI author, I want `?defect_exit:int` (default 2) on all four Door entry points to map non-Fail Cause reports and validator-raised defects to my internal-error exit code, so that Leash can use 70 consistently without changing the existing consumers. ^napp-5e3x

7. As a CLI author, I want `?decode_with_env` on all four Door entry points, receiving the minted Env and the JSON document, so that decoding can use capabilities and report every problem at once — including filesystem ones — instead of the derived decoder. ^napp-5w6t

## Implementation Decisions

- Additive on `run`, `run_with_args`, `run_for_test`, and `run_for_test_with_args`. Omitted options preserve the existing text, exit codes, help metadata and bare-service default exactly; existing consumers need no changes.
- The diagnostic hook receives the original complete message, including any final newline. The returned string is written verbatim once; a JSON-lines renderer supplies its own newline. It is not called on help, version, successful output, consumer-owned direct writes or journal records. Exceptions in a renderer propagate, rather than recursively calling that renderer.
- Cmdliner's error formatter is buffered and flushed before the hook is called. No part of its usage diagnostic is written raw. Existing exit-code mapping remains independent of rendering.
- The four kinds classify reports, not consumer error codes. Plain typed failures are `Validation`; all other reported Causes (including composed Causes and foreign interruptions) are `Defect`. Requested stops remain silent.
- `decode_with_env`, when omitted, leaves `spec.of_yojson` unchanged. When supplied, the Door calls it instead of `spec.of_yojson` on every decode it performs (service start and `config check`), with the pre-config Env it has minted. `spec.env` still applies. A string error is a Config diagnostic and keeps `validation_exit`. A missing required file does not call the decoder. ^napp-5w6t
- `man` and `exits` are forwarded to each command info the Door constructs, not substituted into consumer-supplied command infos. Absent options retain Cmdliner's defaults; supplied exit info replaces its default table without changing evaluation.
- `defect_exit` changes only the exit for reported non-Fail Causes and raised validators; requested stops, typed failures, usage and config/validation rejections retain their existing mappings.
- Test entry points use `'base Env.t` for the bare term builder; production entry points use `Eio_unix.Stdenv.base Env.t`. The term returns the usual deferred `unit -> int`, whose code is returned unchanged. The author owns the orientation's output and any resource scopes; `--help` does not execute its thunk.

## Testing Decisions

- `test/app` tests cite every new story ID: one-line JSON usage output with one hook call, load/decode and multi-error validation, complete defect and typed failure reports, supplied man sections and real exits on every Door-built help path, bare `Command` execution without config/service entry, custom defect exit 70 on program, owned-command, telemetry and validator defects, and an env decoder on startup and `config check` (its value, a filesystem-style error, the minted Env, and an environment override still applied). Existing Door tests guard unchanged defaults and exit handling.
- Gates use an isolated `DUNE_BUILD_DIR=_build_door5`: `@install`, full `dune test`, `@fmt`, and `scripts/caps-gate`, with a 900-second timeout per foreground gate.
- Build Leash, Pie, nema, inn and grip unchanged against a private install via `OCAMLPATH`; nema gets an install built with its own Nix shell's compiler. Remove the isolated build directories afterwards. Do not install into the shared switch or touch running services.

## Out of Scope

Leash's JSON record schema, hints, exit-code table, command grouping choices and orientation content belong to Leash L41. No service restarts, binary replacement, shared-switch installation or commits are part of this delivery.

Verified: test/app covers ^napp-5u8d ^napp-5c2v ^napp-5d7f ^napp-5h4m ^napp-5b9o ^napp-5e3x ^napp-5w6t.
The isolated `@install`, full `dune test`, `@fmt`, and `scripts/caps-gate` passed with `DUNE_BUILD_DIR=_build_door5`. Pie, inn, grip, and committed Leash built against a private install; nema built against an install from its own Nix compiler.
