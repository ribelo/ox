---
status: completed
package: eta_http (WebSocket client; eta, eio, eio.unix, cstruct, OpenSSL)
consumer: Pie Codex Realtime (packages/pie/stt/codex_realtime.ml; read-only)
---

# WebSocket client for Codex Realtime

## Problem Statement

Pie opens authenticated wss:// Codex Realtime sessions, sends JSON text/audio chunks, reads text events, and closes every connection at operation settlement. It also uses local ws:// scripted peers. eta-next has HTTP/1.1 and TLS but no WebSocket upgrade or frames; Pie records a 10-second establishment timeout missing from the old transport.

## Solution

Copy v1's pure RFC 6455 frame codec and regression cases. Add a direct-style `eta_http.Ws_client` over the existing Eio TCP/TLS transport, with explicit switch ownership, a bounded frame/message reader, and typed failures. Only the successful upgrade owns a live socket; connect failures and cancellation close it. The timeout covers DNS, TCP, TLS, and upgrade, never the established stream.

## User Stories

1. As Pie's Codex Realtime session, I want to connect to ws:// local peers and verified wss:// providers with authorization headers, so that I can send and receive session events without changing trust policy. ^nws-a7k2
2. As Pie's session owner, I want establishment bounded by a configurable timeout and typed connection/upgrade/TLS/protocol errors, so that a stalled peer cannot strand a session and failure keeps its diagnostic. ^nws-b9q4
3. As Pie's streaming consumer, I want ordered text and binary receives, text sends, peer ping/pong and orderly close, so that event acknowledgement, audio chunks, and settlement share one owned connection. ^nws-c3m8
4. As a kernel maintainer, I want v1's pure frame codec and its exercised masking/length/control/close vectors copied, so that its protocol constraints survive the rewrite. ^nws-d5r1
5. As a session owner, I want a bounded incoming frame/message and socket closure on cancellation or switch release, so that a hostile peer and an abandoned read cannot retain resources. ^nws-e6t9

## Implementation Decisions

- Copy `v1:lib/http/ws/codec.{ml,mli}`; retain its codec logic and replace its v1 Base64 utility with a small local encoder rather than adding an unapproved dependency. Use the existing OpenSSL SHA-1/RNG and TLS flow; verify upgrade's accept, Upgrade and Connection headers case-insensitively.
- Keep a synchronous `receive` on the calling fiber rather than carrying v1's effect interpreter, daemon reader, and Eta_stream queue. This matches Pie's one-owner consumption and avoids an unowned blocked reader. Serialize writes with an Eio mutex.
- No HTTP response body or content-length handling in a successful 101; reject non-101 as a typed upgrade failure with bounded diagnostic headers. Limit inbound frame and assembled message before allocation. Invalid UTF-8 and unsupported extensions are protocol failures.

## Testing Decisions

- Copy frame codec vectors from the v1 WebSocket test suite into `test/http/ws_client/test_ws_codec.ml`; cite ^nws-d5r1.
- Local plain/TLS servers exercise upgrade, signed accept, headers, framing, ping, close, handshake rejection, timeout, bounds, cancellation and switch-owned socket closure. No remote network calls in normal tests.

Verified: v1 frame codec and vectors; direct Eio ws/wss upgrade, masked text/binary, TLS trust, typed rejection, timeout, fragmentation, bounds, cancellation and switch ownership (14 local tests).
Gates: isolated HEAD plus row 22 passed `dune build @install`, `dune test`, and `dune build @fmt` under `_build_ws_client`; shared-tree integration gates belong to the lead while sibling rows are mid-edit.

## Out of Scope

WebSocket server, compression/extensions, HTTP/2 WebSocket, reconnection, provider-specific JSON, and moving Pie's code in this row.
