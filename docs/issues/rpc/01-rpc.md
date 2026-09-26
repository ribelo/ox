---
status: completed
package: eta_rpc
consumer: Leash milestone 1 (chrome-qnul, chrome-1yn9, chrome-2z2z) and milestone 2 (tab-9x5e)
---

# RPC: request/reply correlation over a message stream

## Problem Statement

CDP over a pipe is JSON messages with an `id`; replies arrive out of order, interleaved with unsolicited events, and multiplexed by `sessionId`. Leash needs to send a request and await exactly its reply, treat everything else as an event stream, and fail every pending request when the pipe dies.

## Solution

`eta_rpc`: `Correlator`, generic over the message type, given a writer and a reader flow plus an id extractor/setter and an optional session-key extractor. It assigns ids, registers a pending slot before writing, resolves the matching reply, streams unmatched messages as notifications, applies optional per-request deadlines, and fails all pending requests with a typed transport-closed error on EOF, error or explicit close.

## User Stories

1. As a service author, I want `Correlator.create ~sw ~read ~write ~id ~set_id ?session` to own one reader fiber and expose `call` and `notifications`, so that a protocol module is a thin layer over it. ^nrpc-wkrp
2. As a service author, I want `call c ?session ?deadline msg` to allocate a fresh id, register the slot, write, and return the reply, so that concurrency is handled once. ^nrpc-pqed
3. As a service author, I want replies matched on (id, session) so that identical ids from different CDP sessions never collide. ^nrpc-3ikx
4. As a service author, I want messages without a pending id delivered in order on `notifications`, a bounded `Eio.Stream` with documented overflow, so that events are never lost silently. ^nrpc-acml
5. As a service author, I want a deadline on `call` to fail that call with ``Timeout`` and drop its slot, so that a hung browser does not hang me. ^nrpc-amni
6. As a service author, I want cancellation of a `call` to drop its slot and propagate as interruption, never as a fabricated reply. ^nrpc-1glx
7. As a service author, I want EOF, a read error, or `close` to reject new calls and fail every pending call with ``Transport_closed`` carrying the cause, so that the registry can tombstone everything at once. ^nrpc-hjv6
8. As a service author, I want a write failure to fail only that call and never retry the write, so that a request whose outcome is unknown is not issued twice. ^nrpc-vnce
9. As a service author, I want `close` to join the reader fiber and settle everything before returning, so that nothing outlives the correlator. ^nrpc-lf9n
10. As a test author, I want the correlator tested with scripted flows: out-of-order replies, interleaved notifications, session collisions, EOF mid-call, deadline, cancellation, and a slow notification consumer. ^nrpc-d96a

## Implementation Decisions

- Framing is not the correlator's job; the caller supplies `read : unit -> msg option` (None on EOF) and `write : msg -> unit` (raises on failure), so NUL-delimited JSON is Leash's ten lines.
- Pending slots: a `Hashtbl` from (id, session) to `Eio.Promise`; a mutex is unnecessary within one domain.
- Deadlines through `Eta.Timeout` with the correlator's clock.
- Notifications: `Eio.Stream` of capacity N; on overflow drop the oldest and increment a counter exposed in `stats`.

## Testing Decisions

- `test/rpc/` with `Eio_mock.Flow`-backed scripted reader/writer and a mock clock; every story cited by name.

## Verification

- `nix develop -c dune build @install` passed.
- `nix develop -c dune test test/rpc` passed (6 tests).

## Out of Scope

JSON knowledge, retries, batching, streaming replies, bidirectional calls from the peer.
