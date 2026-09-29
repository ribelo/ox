---
status: completed
package: ox_http
consumer: Pie migration (row 32; found by the lifecycle_soak WSS fixture)
---

# TLS: a peer's close is an end of stream, and a flow can be closed

## Problem Statement

`Ox_http.Tls_flow` has no close capability, and a peer that closes the TCP connection without a TLS close_notify surfaces to a reader as `Tls_failure "OpenSSL error 2"` rather than end of stream. Many servers (and proxies) close that way after their last message; Pie's Codex Realtime session reads until the server closes, so a clean server close looks like a transport failure.

## User Stories

1. As a TLS client, I want a peer's close — with close_notify, or an unexpected EOF after a complete record — to read as end of stream (`End_of_file`), while a corrupted or truncated record stays a typed TLS failure, so that a server's normal close is not reported as an error. ^nhttp-7pp8
2. As a TLS client or server, I want to close a flow (send close_notify, then shut the socket down) through the flow itself, so that I end sessions cleanly without reaching for the raw socket. ^nhttp-rs5p

## Implementation Decisions

- `Tls_flow.ty` includes `Eio.Resource.close_ty`; `create` takes and returns a closable two-way flow. Explicit `Eio.Flow.close` sends close_notify, drains the alert without waiting for a peer reply, and always releases the raw flow. Repeated close is harmless. Switch release remains the raw socket lifetime backstop; send half-shutdown is not graceful TLS close.
- Track TLS wire record boundaries while feeding the memory BIO. After the handshake, WANT_READ plus TCP EOF is `End_of_file` only at a complete record boundary. Partial headers and payloads stay `Tls_failure`; OpenSSL still authenticates records and reports corrupted ciphertext. Handshake EOF remains a TLS failure.
- WebSocket client cleanup closes the TLS wrapper. HTTP request ownership stays unchanged. Pie fixtures close wrapped TLS flows, and their drain helper no longer hides arbitrary TLS failures.
- Transport EOF is not application success: Pie still reports a WebSocket abnormal close when no WebSocket close frame arrived, and incomplete Codex sessions remain incomplete.

## Testing Decisions

- `test/http/test_tls_flow.ml` (`nhttp-7pp8`): 40,000-byte complete-record TCP EOF with seven-byte application reads and repeated EOF; truncated headers and payloads; corrupted complete ciphertext; bytewise fragmented complete record.
- `test/http/test_tls_flow.ml` (`nhttp-rs5p`): server and client close deliver an OpenSSL ZERO_RETURN before socket EOF; double close is safe; failed or cancelled alert writes still release the socket.
- `test/http/ws_client/run.ml` (`nhttp-rs5p`): public WebSocket close emits a WebSocket close frame followed by TLS close_notify, observable as OpenSSL ZERO_RETURN, and a second close is safe. This regression fails when cleanup bypasses the TLS wrapper.
- Pie `packages/pie/test/realtime_outcomes/test_realtime_outcomes.ml` (`nhttp-7pp8`, `nhttp-rs5p`, `pienext-jlmd`, `pienext-4ps6`): WSS TCP EOF and close_notify before readiness remain `closed (1006)`, not successful acknowledgement; a partial TLS header remains `TLS failed`. All three yield no audio.
- Pie lifecycle-soak and session-ownership WSS fixtures use graceful wrapper close and keep repeated worker/connection ownership assertions (`pienext-jlmd`, `pienext-4ps6`, `piesession-ml14`).

Verified: all nine TLS flow regressions and the full Ox and Pie suites pass. Both repositories pass build `@install`, tests with `EIO_BACKEND=posix`, `@fmt`, and `scripts/caps-gate`; consumer checks use a private Ox prefix. Leash, grip and inn pass build `@install` and full tests unchanged. Nema passes its default build, full tests, `@fmt` and caps gate with Ox rebuilt in its own Nix shell; its pre-existing scratch probe capability omission and Dune formatting failures are repaired separately under `nmacap-7yh7`/`nmacap-ava9`.
