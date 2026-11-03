---
status: completed
package: ox_process, ox_http, ox_sql
consumer: every consumer (Ox-internal; ADR-0010)
---

# Handles with an end are `unique`, and the end consumes them

> Completed 2026-11-03. Verified: stories 7-10 by `Ox_blocking`'s native leases (`test/blocking/safety_native_leases`, installed-API consumer). Stories 1, 2, 5 and 6 are withdrawn, story 3 is covered by `ox-discarded-result`, and story 4 moves to `duplex-halves` story 5; see "Restated 2026-11-03" below.

## Problem Statement

A child process can be signalled after it was waited for, a WebSocket written after it was closed, a pool used after shutdown, a TLS flow closed twice. Each is checked at run time today, or not at all, and each surfaces as a defect in production.

## Solution

Handles with a terminal operation are returned `@ unique`; the terminal operation takes `t @ unique` and consumes it; non-terminal operations borrow (`t @ local`) or thread (`t @ unique -> ... * t @ unique`). Sharing a handle between fibers is then an explicit step (`duplex-halves`, `spawner`), not an accident.

## User Stories

1. As a service author, I want `Ox_process.Child.spawn` to return `Child.t @ unique` and `Child.wait : Child.t @ unique -> status`, with `signal` and `pid` borrowing, so that a signal after the wait is a compile error. ^nown-yxqr
2. As a service author, I want `Ws_client.close`, `Tls_flow.close` and `Ox_sql.Pool.shutdown` to take `t @ unique`, so that use after close and double close are compile errors. ^nown-ubbv
3. As a service author, I want the result of `close` and `shutdown` to be a `result` I cannot silently drop where a gate rule can see it (`raw-concurrency-gate` story 4), so that the close failure at `ws_client.ml:426` is handled or explicitly ignored. ^nown-lis8
4. As a kernel maintainer, I want each handle's internal record to keep shared payloads behind `@@ aliased` fields and threading to be measured (a rebuild per operation, or a module-private `Obj.magic_unique` under the same audit as `Ox.Once`), so that the ownership costs no measurable throughput. ^nown-1hni
5. As a kernel maintainer, I want compile-fail cases (use after close, close twice, signal after wait) beside `once-forks`'s, so that each refusal is pinned. ^nown-ws29
6. As a consumer maintainer, I want Leash, nema, Pie, grip and inn migrated in the same row, each call site either threading the handle or splitting it, so that no consumer stays on a removed signature. ^nown-xbnd

7. As a native adapter author, I want an explicit lease retaining callback resources through physical completion, so that waiter timeout or cancellation cannot release a resource still in use. ^safe-zgfv
8. As a resource owner, I want cancellation before claim, submission rejection and physical completion to release the retained ownership exactly once through the correct owner context, so that resources neither leak nor close early. ^safe-sw86
9. As a maintainer, I want Drain, detach policy and settlement failures accounted for without adding a second cancellation model, so that Eio still owns interruption and native completion remains truthful. ^safe-bt9f
10. As a reviewer, I want one demonstrated native-resource user migrated and the remaining bypass inventory explicit, so that the interface is verified by a real use rather than a hypothetical generic leasing framework. ^safe-m6vf

## Implementation Decisions

Verified pattern (ADR-0010): `close w; write w` is refused ("already been used as unique"). A record with an `aliased` payload must be destructured and rebuilt to be returned `unique` after reading the payload. Handles stored in a Service record and used from several fibers cannot be `unique`; those Services use `duplex-halves` or keep a borrowing API and are listed in this row's notes.

## Restated 2026-11-03

The problem statement is out of date. Each named misuse now has a defined result at run time, and no misuse is a defect:

- `Child.signal` after `await` or `stop` is a no-op, and `stop` is repeatable and safe under cancellation (`lib/process/child.mli`).
- `Pool` operations after `shutdown` return `Error \`Pool_shutdown` (`lib/sql/pool.ml`).
- `Ws_client` operations after the close handshake return `Error (\`Closed _)`.

`Child.t` and `Pool.t` are shared by design: a supervisor waits on a child while another fiber stops it, and a pool exists to be used from many fibers. A `unique` handle refuses exactly that use. It also changes signatures at many call sites in Pie, inn, nema, grip and Leash, only to turn typed run-time results into compile errors. The cost is higher than the gain, so stories 1, 2 (for `Pool.shutdown`), 5 and 6 are withdrawn (^nown-yxqr ^nown-ubbv ^nown-ws29 ^nown-xbnd).

The ownership that prevents a real bug class is the duplex one: row 57's shared TLS buffer. `duplex-halves` gives each half one owner, and the close of a half consumes it. The `Ws_client.close` and `Tls_flow.close` part of story 2 and the throughput measurement of story 4 belong there (^nown-1hni). Story 3 is `ox-discarded-result` (`docs/rules/ox-discarded-result.md`; `raw-concurrency-gate` story 4) (^nown-lis8).

## Testing Decisions

Compile-fail cases; existing process, ws, tls and sql suites pass.

## Out of Scope

Typestate (`ws-typestate`), duplex splitting (`duplex-halves`).
