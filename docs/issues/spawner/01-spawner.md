---
status: ready
package: ox, ox_ipc, ox_http, ox_app
consumer: every consumer (Ox-internal; ADR-0010)
---

# Long-lived forking is a declared `Spawner.t`

## Problem Statement

Services that start fibers after `create` returns (an accept loop, a supervisor, an RPC correlator) keep an `Eio.Switch.t` in their record. Nothing in their type says they can start work later, and nothing stops any other function holding the record from forking onto the root switch.

## Solution

`Spawner.t` is the one global, storable permission to start fibers in a scope. A Service that forks after `create` names `spawner : Ox.Spawner.t` in its `deps`; one that does not, cannot. With `raw-concurrency-gate` the switch itself is no longer reachable.

## User Stories

1. As a service author, I want `Scope.spawner : 'e Scope.t -> Spawner.t` and `Spawner.fork`, `fork_error`, `on_release` with `once-forks`' modes, so that forking later is an explicit capability. ^nspawn-lhyg
2. As a reviewer, I want every Ox Service that forks after creation (`Ox_ipc.Listener`, `Ox_http.Server`, `Ox_rpc.Correlator`, `Ox.Supervisor`, `Ox.Actor`) to take a `Spawner.t` instead of `~sw` where it forks later, so that its signature says so. ^nspawn-g5sr
3. As a reviewer, I want the Door to hand the program a `Spawner.t` for the root scope alongside the switch it hands today, so that a program narrows it the way it narrows caps. ^nspawn-6qtp
4. As a consumer maintainer, I want Leash, nema, Pie, grip and inn moved off stored switches in the same row, so that the gate in `raw-concurrency-gate` can forbid `Eio.Switch.t` in consumer records. ^nspawn-wy83
5. As a kernel maintainer, I want a test showing a Service without a spawner in its deps cannot fork after `create`, so that the property is pinned. ^nspawn-3yv0

## Implementation Decisions

`Spawner.t` wraps the scope's switch (global); its fork functions use `Ox.Once.guard`. It is plain OCaml, verified by construction; no new mode question.

## Out of Scope

Local scopes (`local-scope`).
