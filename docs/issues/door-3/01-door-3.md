---
status: ready-for-agent
package: eta_app
consumer: nema row 31 (U4: nema's CLI contract — help on bare invocation, usage exit 124, its own exit codes 64/65/69/70/75, 130 on interrupt for client verbs)
---

# The Door keeps a program's CLI contract: bare help, usage exit, and its own exit codes

## Problem Statement

nema's CLI prints help when run with no subcommand, exits 124 on a usage error, and gives client verbs their own exit codes (64 config, 65 data, 69 unavailable, 70 internal, 75 temp failure) with 130 on an interrupt. The Door starts the service on a bare invocation, maps every usage error to 2, and renders every program error as 1. Agents and scripts read those codes; the migration must not change them.

## User Stories

1. As a service author, I want `?bare:[ `Service | `Help ]` (default `Service) on `run_with_args` and `run_for_test_with_args`, so that a bare invocation can print the command group's help (exit 0) instead of starting the service. ^napp-k0x0
2. As a service author, I want `?usage_exit:int` (default 2) as the exit code for a command-line parse or usage error, so that my documented code survives. ^napp-1k5x
3. As a service author, I want `?exit_code:('err -> int)` (default `fun _ -> 1`) mapping a program's typed error to its exit code — the service and owned commands alike; defects stay 2. ^napp-j3qu
4. As a CLI author, I want owned commands (`commands_with_env`) to get a runner that returns my exit code directly (e.g. `run_owned_code : (Eio.Switch.t -> int) -> int`) under the Door's signal handling, with a requested SIGINT/SIGTERM stop mapped to `?interrupt_exit` (default 130 for owned commands; the service keeps 0), so that client verbs keep their codes without a side channel. ^napp-izjt

## Implementation Decisions

- Additive: every default preserves today's behaviour; Leash, grip, inn and Pie are unchanged.

## Testing Decisions

- test/app: bare `Help` prints help and never starts the program; a bad flag exits `usage_exit`; `exit_code` maps typed errors (a defect stays 2); an owned command's int is the exit; a real SIGTERM during an owned command exits 130 (reuse the signal fixture).
