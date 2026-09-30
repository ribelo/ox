---
status: in-progress
package: ox_http
consumer: Pie
---

# Quiet keepalives and full-duplex WSS retain their connection and cause

## Problem Statement

Pie’s [long-recording evidence](</home/ribelo/projects/ribelo/pie/docs/issues/long-recording-cutoff/01-ws-ping-limit-cuts-long-dictation.md>) identifies a lifetime budget of 32 pings in one receive as the matching explanation for two 666-second recording cutoffs. Its [WSS investigation](</home/ribelo/projects/ribelo/pie/docs/issues/session-ownership-wss-flake/01-wss-normal-close.md>) reproduces ciphertext-buffer overlap, bad-record-MAC failures, and a secondary normal close masking the TLS cause. Pie is a read-only consumer during this repair; installed packages and services are not changed.

## User Stories

1. As Pie’s streaming receiver, I want to answer quiet keepalive pings indefinitely while rejecting a control-frame flood, so that a long recording has no transport-imposed lifetime. ^wsduplex-h6pk
2. As Pie’s full-duplex TLS connection, I want in-flight reads and writes to own disjoint ciphertext buffers and writers to preserve wire order without blocking sends behind an idle read, so that concurrent audio and events cannot corrupt authenticated records. ^wsduplex-j4rn
3. As Pie’s fail-fast session, I want the first terminal transport cause published before shutdown can suspend and retained by later operations, so that a TLS authentication failure cannot become a synthetic normal close. ^wsduplex-v8mq

## Implementation Decisions

- WebSocket Ping and Pong use one connection-wide token bucket: capacity 32 frames, replenishment 32 frames/second from the existing clock capability. Application messages and receive-call boundaries do not reset it. Backwards clock adjustment does not grant tokens; quiet keepalives have no lifetime count.
- WebSocket terminal state retains the first cause before shutdown. Send, receive and failed-connection close return it; explicit successful close stays idempotent. Cancellation propagates unchanged. One receiver plus concurrent senders within one Eio domain is the contract.
- TLS buffers, writer serialization and WANT_READ/WANT_WRITE/state ownership are audited without a lock spanning a blocking raw read.

## Testing Decisions

- Mock-clock WebSocket regression: one receive survives 100 pings spaced 20 seconds apart, answers each payload, then returns a message. Ping/Pong bursts fail at the time budget; application messages cannot reset it.
- Deterministically park shutdown after an injected TLS failure, run a concurrent sender, and assert the same TLS cause both before and after shutdown. A fail-fast pair must expose that cause even when it cancels the suspended receiver.
- TLS regression: park a raw read while yielding a raw write, assert nonaliasing and wire ordering, then stress concurrent loopback send/receive across many records with zero MAC failures.
- Gates: private memory-capped @install, dune test, @fmt; caps-gate without the memory cap. Leash, nema, inn and grip are build-only consumers of a private install via OCAMLPATH. No commits, shared-switch installation, or service changes.

## TLS audit (wsduplex-j4rn)

Pie's overlap probe is the cause: `feed` parks in `Eio.Flow.single_read` on the one `wire` buffer while a concurrent `drain` writes ciphertext into that same buffer. Authenticated records then fail with bad record MAC. A per-drain buffer was only a counterfactual; the repair below is the concurrency design.

- `inbound` and `outbound` are disjoint 16384-byte buffers. `inbound` stays live for the whole raw read, including the park. `outbound` stays live for the whole raw write. `write_mu` makes that write exclusive, so two drains cannot share it or byte-interleave records.
- `write_mu` serializes writers and is never held across a raw read. A successful send takes `write_mu` and `ssl_mu` only, so an idle parked read cannot block it. The parked-read test deadlocks if that rule is broken: the write must finish before the read is released.
- `read_mu` covers only the raw read and record-boundary state. A reader that must flush before `WANT_READ` uses `try_lock` on `write_mu`. If a writer is already blocked in a raw write, the reader does not wait; that writer already owns the in-flight ciphertext, and waiting would stall the read that frees the TCP window.
- `ssl_mu` covers `SSL_read`, `SSL_write`, handshake, shutdown, and BIO calls only. It is never held across a socket operation. OpenSSL's SSL object is not entered concurrently. Locks use `Eio.Mutex.use_ro`, so expected failure and cancellation unlock instead of poisoning; close and the other direction still run.
- `WANT_READ` on write drains under `write_mu`, drops that lock, then feeds. Other writers are not stuck behind that read. This path waits on `read_mu` only when OpenSSL itself needs inbound ciphertext and a receiver is already parked. `WANT_WRITE` still fails when the write BIO is empty, and otherwise drains and retries; a memory BIO does not legitimately return it.
- Bytes already taken from the socket are fed to the BIO under `Cancel.protect`, so cancellation cannot drop a consumed record. Close still sends close_notify without waiting for the peer, holds `write_mu` across shutdown and the alert drain so the alert is not spliced into another record, and closes `raw` from `Fun.protect` if the alert write fails or is cancelled (nhttp-rs5p).

Testing notes, `test/http/test_tls_flow.ml`:

- Parked raw read, canary filled in the caller's buffer, eight yields inside the raw write before the socket write, read released only after that write returns. Asserts distinct bigarrays, stable write bytes across the yields, intact canary, and a decrypted `ping`/`pong` round trip.
- Two concurrent writers, disjoint alphabets, increasing frames (4000 each). The peer receives every byte and each payload is an in-order subsequence. A byte-interleaved record fails MAC before that check.
- Cancel the parked read, then send and receive. The send is not stuck, and the next read is not `Eio.Mutex.Poisoned`.
- Loopback stress: 60 messages each way, lengths 1, 64, 4096, 16384 and 40000, both sides sending and receiving together. Zero `Tls_failure` (no bad record MAC). Existing nhttp-7pp8 and nhttp-rs5p cases still pass.

Verified on a private `_build_tls` with `ulimit -v 16777216`: `dune build @install`, `dune test`, and `dune build @fmt` exited 0. `scripts/caps-gate` without the ulimit exited 0. The build directory was removed. No commit.
