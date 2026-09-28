---
status: ready-for-agent
package: eta_http
consumer: Pie migration (row 32; found by the lifecycle_soak WSS fixture)
---

# TLS: a peer's close is an end of stream, and a flow can be closed

## Problem Statement

`Eta_http.Tls_flow` has no close capability, and a peer that closes the TCP connection without a TLS close_notify surfaces to a reader as `Tls_failure "OpenSSL error 2"` rather than end of stream. Many servers (and proxies) close that way after their last message; Pie's Codex Realtime session reads until the server closes, so a clean server close looks like a transport failure.

## User Stories

1. As a TLS client, I want a peer's close — with close_notify, or an unexpected EOF after a complete record — to read as end of stream (`End_of_file`), while a corrupted or truncated record stays a typed TLS failure, so that a server's normal close is not reported as an error. ^nhttp-7pp8
2. As a TLS client or server, I want to close a flow (send close_notify, then shut the socket down) through the flow itself, so that I end sessions cleanly without reaching for the raw socket. ^nhttp-rs5p

## Testing Decisions

- Loopback TLS pair: peer closes without close_notify after a full message → reader sees the message then End_of_file; peer sends garbage mid-record → typed failure; `close` delivers close_notify the other side reads as End_of_file.
