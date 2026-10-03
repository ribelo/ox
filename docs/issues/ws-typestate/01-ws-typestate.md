---
status: ready
package: ox_http
consumer: every consumer (Ox-internal; ADR-0010)
---

# WebSocket phases and close frames in the type

## Problem Statement

`Ws_client` checks at run time that a close code is valid, that a reason fits 123 bytes (`ws_client.ml:320-321`), and that frames are not sent after closing (`ws_codec.ml` raises `Invalid_argument` for fragmented control frames, oversized control payloads, invalid close codes, a mask that is not four bytes). Each is an agent-reachable defect.

## Solution

Constructors for the values (`Close_code.t`, `Close_reason.t`, `Mask.t`, `Control_payload.t`) and a phase parameter on the owned writer from `duplex-halves`: `[ `Open ] writer` sends data and closes into `[ `Closing ] writer`, which can only await the peer's close. Phantom state is sound here only because the writer is `unique` (an alias could keep the old phase).

## User Stories

1. As a transport author, I want `Close_code.of_int : int -> (t, _) result` with named constants (`normal`, `going_away`, ...) and `Close_reason.of_string` refusing more than 123 bytes or invalid UTF-8, so that `close` cannot be called with an invalid frame. ^ntstate-j6u0
2. As a transport author, I want `Ws_codec`'s control-frame and mask constructors to take these types, removing its `invalid_arg` sites, so that a malformed frame cannot be built. ^ntstate-s6um
3. As a transport author, I want `('phase) Ws_client.writer` with `send : [ `Open ] writer @ unique -> ... -> [ `Open ] writer @ unique` and `close : [ `Open ] writer @ unique -> ... -> [ `Closing ] writer @ unique`, so that a send after close is a compile error. ^ntstate-iwqj
4. As a kernel maintainer, I want compile-fail cases for each, so that the refusals are pinned. ^ntstate-muq6

## Implementation Decisions

After `owned-handles` and `duplex-halves`. Decoding a peer's frame still validates at run time and returns typed errors; only frames we build are typed.

## Out of Scope

HTTP/1 request phases.
