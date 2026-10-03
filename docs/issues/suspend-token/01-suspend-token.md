---
status: ready
package: ox, ox_http, ox_ipc, ox_rpc, ox_blocking
consumer: every consumer (Ox-internal; ADR-0010)
---

# Suspension is a `yielding` capability, so critical sections cannot suspend

## Problem Statement

A fiber that suspends inside an actor handler, an agent closure, a `Cancel.protect` or a mutex critical section stalls everything waiting on it; inside a Stdlib mutex it blocks the domain. ADR-0010 found that `unyielding` alone does not stop this (`Eio.Fiber.yield` and `Effect.perform` are not mode-checked), but a token does: if every suspending Ox operation needs `io : Io.t @ yielding`, any closure that uses one is `yielding`, and an `unyielding` parameter refuses it ("The value io is yielding but is expected to be unyielding"). This is Jane Street's `Await.t @ local`.

## Solution

`Ox.Io.t`, handed to the program by the Door, to each fork body by `Scope.fork`, and required by every Ox operation that may suspend. Critical sections (`Ox.Mutex.with_access`, `Ox.Cancel.protect`, `Actor` handlers, `Agent` closures, `Status` queries) are `unyielding`.

## User Stories

1. As a service author, I want `Ox.Io.t` passed to the program and to every fork body (`Scope.fork : 'e t -> (Io.t @ yielding -> unit) @ once -> unit`), never stored globally, so that the right to suspend follows the fiber. ^nyield-bfwl
2. As a service author, I want every Ox operation that may suspend (`Channel.send/receive`, `Select`, `Timeout`, `Retry` delays, `Rate_limiter.run`, `Actor.ask`, `Agent.get`, `Scope.await`, `Ox_http` and `Ox_ipc` I/O, `Ox_blocking.run`) to take `~io`, so that suspension is visible in the signature. ^nyield-rqjy
3. As a service author, I want `Ox.Mutex.with_access`, `Ox.Cancel.protect`, `Actor.create ~handle`, `Agent` closures and `SERVICE.status` typed `unyielding`, so that suspending inside them is a compile error. ^nyield-0o4o
4. As a reviewer, I want the shape and names to follow `Await.t` (`Io.yield`, termination vs cancellation kept for `cancellation-value`), so that a later swap to `await` is mechanical. ^nyield-6yub
5. As a kernel maintainer, I want compile-fail cases (suspend in each critical section; token captured by raw `Eio.Fiber.fork`, which Eio's legacy signature already refuses) and controls through `let%bind`, so that the refusals are pinned. ^nyield-9spl
6. As a consumer maintainer, I want the threading cost measured on Leash and nema before migration (sites per kloc, like caps' ^ncaps-21nk) and recorded here, so that the decision to migrate consumers is made on numbers. ^nyield-pqxk

## Implementation Decisions

Verified (ADR-0010) with a one-field `io = { suspend : unit -> unit } [@@unboxed]` token at `global yielding`: correct use compiles; suspension in an `unyielding` section and capture by raw `Eio.Fiber.fork` are refused; `let*` refuses the token, explicit `bind` accepts it — hence the dependency on `ppx-let`. Raw Eio suspension (`Eio.Fiber.yield`, `Eio.Stream.take`) does not need the token, so `raw-concurrency-gate` must also refuse Eio's suspending operations outside `lib/`; story 2's list is the replacement set.

## Out of Scope

Domain-level blocking (`Ox_blocking` already runs on systhreads).
