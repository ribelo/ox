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

1. As a service author, I want `Ox.Io.t` minted only by the Door (the root) and handed to each fork body fresh, never by a public `with_io`, so that a critical callback cannot mint its own token and suspend (the provider-escape program compiles when a public provider exists — row 75 Findings). ^nyield-bfwl
2. As a service author, I want every Ox operation that may suspend to take `~io` — the inventory in row 75's Findings §1, including forking (Eio's fork requeues the parent), release registration (`on_release` can run the release synchronously on a finished switch), nested `Scope.run` (which consumes the current token rather than minting one), logging while it can park, and the I/O packages — so that suspension is visible in every signature. ^nyield-rqjy
3. As a service author, I want two kinds of section: *must-not-suspend* (`unyielding`: `Actor` handlers, `Agent` closures, status functions, short `Ox.Mutex` sections, sections guarding C state) and *may-suspend* (`yielding`, taking `~io`: `Ox.Mutex.with_access_waiting`, `Ox.Cancel.protect` around drains and cleanup, condition waits, writes under a transport lock), so that the compiler refuses suspension exactly where a contract forbids it and nowhere else. ^nyield-0o4o
4. As a reviewer, I want deferred callback fields (reporter emitters, select clause waits, rate-limiter sleeps) to receive a fresh `io` when invoked instead of capturing one at construction, so that constructors stay pure and no token is stored. ^nyield-6yub
5. As a service author, I want `Ox_observability.Logger` to never suspend — emit try-adds into a bounded queue drained by one writer fiber, overflow counted and reported — so that logging is allowed inside must-not-suspend sections (row 75: it removes Leash's status-warning and Actor-info conflicts). ^nyield-9spl
6. As a consumer maintainer, I want Leash and nema migrated, after their current violations are fixed — Leash `tabs.ml` declared-synchronous sections calling `Actor.ask` (721–725 with 1078, 1098, 1188, 1305) and `Learning.status` waiting on a mutex and a warning log; nema `Gate.with_write ~on_waiting` reaching `Logger.span`/`info` against `Gate.mli`'s contract — and Pie, inn and grip after them the same way, so that the guarantee holds where the code runs, not only in ox (row 75 recommends migration). ^nyield-pqxk
7. As a reviewer, I want any no-`io` facade kept for migration marked unchecked and refused inside checked critical code by the gate, so that a legacy wrapper cannot carry suspension into a must-not-suspend section. ^nyield-k7r2
8. As a kernel maintainer, I want compile-fail cases (suspend in each must-not-suspend kind; token captured by raw `Eio.Fiber.fork`; a token minted inside a critical callback) and controls through `let%bind`, so that the refusals are pinned. ^nyield-x5ce

## Implementation Decisions

Verified (ADR-0010) with a one-field `io = { suspend : unit -> unit } [@@unboxed]` token at `global yielding`: correct use compiles; suspension in an `unyielding` section and capture by raw `Eio.Fiber.fork` are refused; `let*` refuses the token, explicit `bind` accepts it — hence the dependency on `ppx-let`. Raw Eio suspension (`Eio.Fiber.yield`, `Eio.Stream.take`) does not need the token, so `raw-concurrency-gate` must also refuse Eio's suspending operations outside `lib/`; story 2's list is the replacement set.

## Out of Scope

Domain-level blocking (`Ox_blocking` already runs on systhreads).