---
status: ready
package: ox, ox_app, ox_http, ox_observability, ox_ai, ox_json, ox_rpc, ox_blocking
consumer: every consumer (Ox-internal; ADR-0010)
---

# The kernel applies ADR-0008 to itself

## Problem Statement

ADR-0008 says values with constraints are their own modules with smart constructors. The kernel does not do it for its own arguments: 107 `invalid_arg` sites check capacities ≥ 1, concurrency ≥ 1, byte limits ≥ 0, ports, a 32-hex span id (`logger.ml:319`), and mutually exclusive Door options (`ox_app.ml:180-183`, `?telemetry` vs `?telemetry_result`). Four Door entry points carry 25–40 optional arguments each; their invalid combinations are found at run time or by Cmdliner.

## Solution

Small abstract types with constructors, used in every signature that checks today; and one Door spec record whose mutually exclusive choices are variants.

## User Stories

1. As a service author, I want `Ox.Capacity.t` (≥ 1), `Ox.Concurrency.t` (≥ 1) and `Ox.Byte_limit.t` (≥ 0) with `of_int : int -> (t, [> `Invalid ]) result` and literals for common values, used by `Channel`, `Actor`, `Agent`, `Concurrent.for_each`, `Rate_limiter`, `Ox_json.parse`, `Ox_http` limits, `Ox_ai.Transport` and `Ox_blocking.Pool`, so that these `invalid_arg`s disappear. ^nparse-gb03
2. As a service author, I want `Ox_observability.Span_id.t` (32 lowercase hex) and `Ox_http.Port.t`, so that `Logger.span` and `Service` stop validating. ^nparse-rdst
3. As a service author, I want one `Ox_app.Door.spec` record built from defaults by functional update, with `telemetry : [ `None | `Infallible of ... | `Fallible of ... ]`, `bare : [ `Service | `Help | `Command of ... ]` and commands as one list, and `Ox_app.run : spec -> program -> int`, so that every exclusive choice is a variant and a new option is a field, not an optional argument. ^nparse-8wb9
4. As a service author, I want `run`, `run_with_args`, `run_for_test`, `run_for_test_with_args` and `run_simple` reduced to `run` and `run_for_test` over the spec, with an `Ox_app.Door` migration note, so that the Door has one shape. ^nparse-xubq
5. As a consumer maintainer, I want Leash, nema, Pie, grip and inn moved to the spec record in the same row, so that no consumer keeps the old entry points. ^nparse-ko03
6. As a kernel maintainer, I want the remaining `invalid_arg` sites listed in this spec with the reason each stays (internal invariants such as `router_slice` bounds), so that the count is a decision, not a drift. ^nparse-x2iu

## Out of Scope

Typing values decoded from the wire (they stay validated at the edge with typed errors).
