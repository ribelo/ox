---
status: completed
package: eta_http (client only: h1, TLS via OpenSSL), copied codecs from v1
consumer: Leash milestone 5 (drive-zml5, drive-ls3c: System One and the text helper are HTTPS POSTs)
---

# HTTP/1.1 client over TLS, direct style

## Problem Statement

Leash's drive loop makes two kinds of HTTPS request — a System One evaluation and a chat completion — and eta-next has no HTTP client at all. v1 has a complete, hardened HTTP/1.1 codec, an OpenSSL binding, and an Eio transport, all written against `Effect.t` in the transport and pure in the codec.

## Solution

`eta_http`: the v1 HTTP/1.1 codec (`lib/http/h1`, pure) and OpenSSL binding (`lib/http_tls_openssl`, C stubs plus a pure state-machine driver) copied file by file; a direct-style Eio transport (connect, TLS handshake, write request, read response) rewritten from `lib/http_eio/{transport,tls,h1,client}`; one `Client` with a request function, bounded bodies, deadlines, and idle-timeout. Client only: no server, no HTTP/2, no WebSocket until a consumer pulls them.

## User Stories

1. As a service author, I want `Client.create ~sw ~net ~clock ?tls ()` and `Client.request client ~method_ ~url ?headers ?body ?deadline ?response_idle ()` returning `(response, error) result` with status, headers and a bounded body, so that an HTTPS POST is one call. ^nhttp-irnw
2. As a kernel maintainer, I want the HTTP/1.1 request writer and response parser copied from `v1:lib/http/h1` with their tests, so that the proven codec is not rewritten. ^nhttp-qvak
3. As a kernel maintainer, I want the OpenSSL binding copied from `v1:lib/http_tls_openssl` (C stubs, memory-BIO driver, system trust store, TLS 1.2/1.3 policy, peer verification on), so that TLS is the same code that has been in production. ^nhttp-gcka
4. As a service author, I want TLS to verify the peer against the system trust store by default with SNI, and a typed ``Tls of reason` failure otherwise, so that a misconfigured host cannot silently downgrade. ^nhttp-5nqk
5. As a service author, I want a per-request deadline covering connect, handshake, write and read, and a separate response-idle timeout (fail if no bytes arrive for the duration), so that a stalled server is cut off without killing a slow-but-progressing one. ^nhttp-hmrw
6. As a service author, I want response bodies bounded (`?max_body_bytes`, default 1 MiB) with ``Body_too_large` on overflow after the connection is dropped, so that a peer cannot make me allocate unboundedly. ^nhttp-xj7z
7. As a service author, I want 3xx responses returned as-is (no automatic redirect following), so that credentials are never forwarded to another host. ^nhttp-0qob
8. As a service author, I want connections closed after each request in this version (no pool), with the option of `Connection: keep-alive` reserved for a later story, so that the client is small and its lifetimes obvious. ^nhttp-jdb0
9. As a service author, I want typed errors — ``Connect`, ``Tls`, ``Timeout`, ``Idle_timeout`, ``Protocol of string`, ``Body_too_large`, ``Closed` — and never an exception for a network condition, so that callers handle failures by variant. ^nhttp-ed7t
10. As a service author, I want cancellation during any phase to close the socket and propagate as interruption, so that a cancelled request leaves nothing open. ^nhttp-6a47
11. As a test author, I want a local plaintext and a local TLS test server (self-signed, trust injected through `?tls`) under `test/http/`, so that every story runs offline, plus one live smoke against `https://example.com` behind an environment flag. ^nhttp-j0bc
12. As a kernel maintainer, I want `eta_http` to depend on `eta`, `eio`, `eio.unix`, the OpenSSL C library and nothing else, recorded in ADR-0007, so that the dependency policy holds. ^nhttp-6c3d

## Implementation Decisions

- Copy: `git show v1:lib/http/h1/*`, `v1:lib/http_tls_openssl/*` (including `tls_openssl_stubs.c`, `tls_openssl_alloc.{c,h}`, the dune with the C stanza), and their tests; strip `Effect.t` where any appears in the codec (there should be none).
- Rewrite: the Eio transport as plain functions over `Eio.Net` and `Eio.Flow`; the TLS flow as an `Eio.Flow.two_way` wrapper driving the memory BIO (v1's `tls_eio.ml` is the reference for the state machine, 677 lines, rewritten not copied).
- Deadlines through `Eta.Timeout`; idle timeout as a per-read `Timeout`.
- URL parsing: the minimal parser from `v1:lib/http_eio/url.ml` if pure, else a fifty-line one.

## Testing Decisions

- `test/http/`: codec and OpenSSL binding regression tests copied; transport tests against local servers for every error variant, deadline and idle timeout with short local delays, and cancellation mid-read verified by peer-observed socket closure.

Verified: copied v1 codecs and OpenSSL binding, direct Eio transport, local plaintext/TLS fixtures, bounded framing, deadlines, idle reads, typed errors and cancellation.
Gates: `nix develop -c dune build @install`, `nix develop -c dune test`, `nix develop -c dune build @fmt`; live smoke is opt-in with `ETA_HTTP_LIVE_SMOKE=1`.

## Out of Scope

HTTP/2, WebSocket, server, connection pooling, proxies, compression, cookies.
