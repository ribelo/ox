---
status: done
package: ox_http
consumer: Exergy providers; existing HTTPS consumers
priority: P0
---

# HTTP client: final response heads and bounded body disposition

## Problem Statement

The direct Eio client already returns a bounded response, but collapses body acquisition failures into the same flat errors as failures before headers. Exergy needs HTTP 401 to remain a browser-login response even when its body never arrives, and HTTP 200 with a failed body to retain status 200. Different providers admit bodies differently. Independently, the current reader returns informational 1xx heads as completed responses and bounds each trailer line but not the trailer block. These are native client contract defects, not requests for an Eta stream runtime.

## Solution

Extend the existing one-shot request operation with explicit caller-owned final-head/body disposition and phase-aware typed failures. Keep the final head on body acquisition errors, including the whole-request deadline. Consume informational responses until a final head, reject unsupported upgrades, and bound all framing sections. The request owns and closes the connection; no stream escapes it.

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
12. As a kernel maintainer, I want `ox_http` to depend on `ox`, `eio`, `eio.unix`, the OpenSSL C library and nothing else, recorded in ADR-0007, so that the dependency policy holds. ^nhttp-6c3d
13. As a provider author, I want failures before a final response head distinguished from failures while acquiring its body, so that transport failure does not erase a known HTTP status. ^nhttp-dlp2
14. As a provider author, I want every post-head body failure to retain the final status, ordered headers and typed reason, so that HTTP 200 with a broken body is not classified as a connection failure. ^nhttp-j7cz
15. As a provider author, I want response-head metadata retained on fixed-length truncation, malformed chunks, oversized bodies, post-head connection/TLS failure and response-idle timeout, so that all body acquisition failures have the same provenance. ^nhttp-uhrh
16. As a provider author, I want a whole-request deadline expiring after the final head to retain that head, while expiration before it remains a pre-head timeout, so that the deadline wrapper does not flatten the phase distinction. ^nhttp-w60z
17. As a provider author, I want to choose bounded body acquisition or skip-and-close from the final status and headers for each request, so that an authentication response can be classified without waiting for an unwanted body. ^nhttp-3bbt
18. As a provider author, I want skip-and-close to return the final head with an explicitly skipped body rather than a fabricated successfully-read empty body, so that no response stream or connection lease escapes the request. ^nhttp-w5yp
19. As an IBKR Gateway author, I want a 401 with a stalled, oversized or malformed body to be returned when my policy skips it, so that browser-login classification is independent of unread content. ^nhttp-jxpd
20. As a provider author, I want policies that read only 2xx, skip only 401, or read every status to remain caller-owned, so that the kernel does not impose one provider authentication policy. ^nhttp-v147
21. As a service author, I want read and skip paths to close their one-shot connection on every exit, so that policy rejection, timeout, cancellation and defects do not leak sockets. ^nhttp-dgoe
22. As a service author, I want external Eio cancellation and defects, including defects in the head-policy callback, to propagate with their original backtraces rather than becoming transport errors, so that structured concurrency remains honest. ^nhttp-hpo2
23. As an HTTP client author, I want 100 and 103 response heads consumed until the final response arrives, including split network reads and multiple informational heads, so that an interim status is never returned as a completed request. ^nhttp-oaw6
24. As an HTTP client author, I want unsupported 101 protocol switching rejected explicitly, so that a one-shot HTTP client does not claim to own an upgraded transport. ^nhttp-0d9e
25. As an HTTP client author, I want informational-head acquisition bounded by a documented cumulative byte budget and the same deadline/idle rules as final-head acquisition, so that endless progress responses cannot evade finite parsing limits. ^nhttp-ey81
26. As an HTTP client author, I want chunked trailers bounded cumulatively as well as per line, with a documented finite limit and a typed protocol failure after the head, so that endless short trailers cannot evade the body bound. ^nhttp-bx60
27. As a test author, I want no-body HEAD/204/304 responses and empty, fixed-length, chunked and close-delimited bodies exercised through the public request API under both dispositions, so that new head handling does not regress supported framing. ^nhttp-8ixg
28. As a kernel maintainer, I want scripted plaintext/TLS server regressions for head provenance, disposition, informational heads, bounded trailers and cleanup, so that defect-specific regressions fail on the audited implementation and pass on the replacement while preservation fixtures stay green. ^nhttp-32fq

## Implementation Decisions

- Direct Eio execution with typed results. Existing explicit switch, network, clock, TLS trust, deadline, response-idle and body-limit dependencies remain; there is no interpreter, transport registry or process-global client.
- Represent pre-head failure, successful read, explicit skip and post-head failure honestly. A skipped body must be distinguishable from a genuinely empty body. The body-failure reason is nonrecursive and accompanied by the final status and headers.
- The caller supplies a small final-head disposition function; it runs once for the final response, never for informational heads. Provider status/authentication rules and retry policy stay outside the kernel. A body failure does not trigger a second request.
- Preserve the existing HTTP/1.1 codecs and OpenSSL trust behavior; make the API express the current contract and update its consumers instead of introducing a legacy overload or fallback path.
- Header/trailer limits are documented finite parsing budgets, separate from the payload-byte budget. Each head and framing line is bounded by 32 KiB; a head admits at most 256 fields. Informational heads share a cumulative 32 KiB wire-byte budget, and trailers have an independent cumulative 32 KiB budget, including CRLF.
- Post-head failures now use `Body { status; headers; reason }`, with ordered duplicate headers and a nonrecursive reason. This supersedes the original flat post-head `Body_too_large`/`Closed`/timeout outcomes without changing stories 1–12; successful bodies are explicitly `Read bytes` or `Skipped`. No legacy overload remains.
- Externally imposed Eio interruption remains an exception. Explicit request deadlines retain their typed timeout meaning and response phase. Defects and callback exceptions are not caught as expected HTTP failures.

## Testing Decisions

- Confirmed seam: public client calls against scripted local plaintext and TLS servers, with latches for head sent, body stalled and peer closure. Fakes do not replace the parser or deadline wrapper.
- Assert status, duplicate-header preservation and typed reason for truncated fixed/chunked data, over-limit data, idle timeout and whole-request timeout after a head; compare a pre-head timeout without invented metadata. Use a post-head TLS failure only with a deterministic transport fixture, not a timing-dependent close.
- For skip, send a head but never provide the body; completion must precede the server releasing its body latch, and the server must observe connection closure. Assert that the policy was called once and only for the final head.
- Exercise the three consumer dispositions independently; a 401 skip must not accidentally establish a global non-2xx rule. Cover a 401 read when the caller requests it.
- Feed 100 then 200, 103 then 100 then 200, split/coalesced heads, EOF before a final head, unsupported 101, informational-budget exhaustion, and many short trailers crossing the cumulative bound. Oversized trailers retain the already-known final head.
- External cancellation during connect/head/body and a raising disposition function must terminate the request, close the connection and preserve the exception/backtrace. Use outer test timeouts only as deadlock guards. Existing framing, trust, request validation, deadline and body-limit suites remain in force; names cite the new IDs.

## Out of Scope

Streaming bodies, pooling, redirect following, WebSocket upgrades, HTTP/2, transparent retry, provider authentication, a generic HTTP tracer, and recreating Eta request/response wrappers. Compression is not an established Exergy prerequisite; no provider currently negotiates or decodes gzip/deflate/br. Do not add decompression incidentally.

## Further Notes

- Audit: 2026-10-04. Relevant source is unchanged between audited Ox revision `08c6fc8f` and `72af4cde`. Original stories retain their IDs; reopening does not invalidate earlier delivery. Earlier green tests did not cover these response-phase contracts. No implementation changes or newly added regression tests were made in this audit; passing existing baseline gates does not establish the new stories.
- Evidence: [client reader:103–187](<../../../lib/http/client.ml#L103-L187>), [deadline/error wrapper:189–267](<../../../lib/http/client.ml#L189-L267>), and [existing HTTP tests](<../../../test/http/run.ml>).
- Consumer acceptance evidence: [Gateway tests:451–544](</home/ribelo/projects/exergy/lib/ibkr/test/test_ibkr.ml#L451-L544>), [Gateway admission:678–699](</home/ribelo/projects/exergy/lib/ibkr/ibkr.ml#L678-L699>), [Flex admission:953–965](</home/ribelo/projects/exergy/lib/ibkr/ibkr.ml#L953-L965>), and [Yahoo admission:828–850](</home/ribelo/projects/exergy/lib/yahoo/yahoo.ml#L828-L850>).
- Protocol role: non-upgrading HTTP/1.1 user agent. [RFC 9110 §15.2](<https://www.rfc-editor.org/rfc/rfc9110.html#section-15.2>) requires parsing one or more informational responses before a final response; [§15.2.2](<https://www.rfc-editor.org/rfc/rfc9110.html#section-15.2.2>) describes switching protocols. [RFC 9112 §7.1.2](<https://www.rfc-editor.org/rfc/rfc9112.html#section-7.1.2>) describes the trailer section. The finite trailer budget is local availability policy, not a numerical RFC requirement. Implementers must refresh current RFC status and applicable errata; this scoped audit does not certify full HTTP conformance.
- Trust boundary: provider/proxy bytes are untrusted. Availability impact is misleading completion on 1xx or unbounded framing work, not an established credential leak or cited CVE. Preserve verified TLS and never attach authentication headers or raw payloads to diagnostic output.
- Exergy integration follows only after this capability lands: providers pass their explicit 16 MiB limits where required and classify the new native outcomes directly. No provider-specific error variants belong in Ox.

Verified 2026-10-04: `nix develop -c dune runtest test/http --force` passed 71 HTTP tests (31 new final-head/disposition cases) and 25 preserved WebSocket tests.
[Test_client_heads](<../../../test/http/test_client_heads.ml>) covers provenance, explicit caller policies, all framing/skip paths, informational and trailer boundaries, mock-clock deadlines/idle, real TCP/TLS faults, cleanup, cancellation and original callback traces; [run](<../../../test/http/run.ml>) preserves the original transport, trust and codec regressions.

