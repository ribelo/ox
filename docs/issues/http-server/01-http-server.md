---
status: completed
package: eta_http (HTTP/1.1 server, router, service helpers)
consumer: inn (local telemetry HTTP routes), nema (local API HTTP server)
---

# HTTP/1.1 server and route helpers

## Problem Statement

inn serves OTLP and query routes through a routed HTTP/1.1 listener; nema serves local JSON endpoints using HTTP/1.1 request and response bodies. eta-next has only an HTTP client. The v1 connection uses `Effect.t`; its HTTP server model and router path matcher are pure, while its service extractors compose effects. The consumers need one `eta_http` package, not a separate service package.

## Solution

Add `Eta_http.Server` for requests, bounded body reads, responses and an Eio HTTP/1.1 listener (including an existing listening socket and a stop promise); `Eta_http.Router` for v1's pure path matching; and `Eta_http.Service` for method-aware route registration, query/parameter/body extractors and JSON responses. Copy v1's pure path matching and corresponding tests; carry over only the pure server model needed by these consumers. Rewrite the Eio connection and effectful helpers in direct style with typed failures and scoped socket ownership.

## User Stories

1. As inn, I want to serve HTTP/1.1 on an address or a caller-owned listening socket until my stop promise resolves, with in-flight requests drained for a bounded time and connections cleaned up, so SIGTERM can finish current telemetry requests before closing the store. ^hserv-a7k2
2. As nema, I want a direct-style request exposing method, path and bounded readable body and a response with status, headers and text/JSON body, so local API routes can parse JSON and return typed failures without `Effect.t`. ^hserv-b8m4
3. As inn, I want method-aware routes with named path parameters, a compiled snapshot, custom 404 and 405 handlers and an Allow header list, so endpoint declarations and aliases dispatch without mismatching methods. ^hserv-c9n6
4. As inn, I want query parsing, header lookup, a required path parameter and a bounded text-body extractor, so query APIs and OTLP ingestion reject malformed or oversized input with typed errors. ^hserv-d2p8
5. As a maintainer, I want v1's pure router path matcher and its regression tests copied into the HTTP package, including static, named, catch-all, prefix/suffix and escaped-brace paths, so established matching behavior is preserved. ^hserv-e3q9
6. As a maintainer, I want local-only server tests for persistent requests, malformed framing, oversized headers/bodies, connection closure and interruption, so the rewritten connection cannot strand a listener or accept a dangerous request. ^hserv-f4r0

## Implementation Decisions

- Copy the relevant pure `v1:lib/router/` matcher files and `v1:test/router/test_eta_router.ml`, adapting only module names and dependencies to `Eta_http.Router`; copy pure server request/response shapes as applicable without importing `Effect.t`.
- Rewrite `v1:lib/http_eio/h1_server_connection.ml` as a direct-style Eio connection; take only h1 listener/socket ownership logic from the effect-free `v1:lib/http_eio/server.ml`, not its h2/TLS/runtime machinery.
- Replace v1 `eta_http_service` and `eta_http_service_eio` with `Eta_http.Service` inside `eta_http`; implement only `Json.response`, `Req.header`, `Extractors.Query.all`, `Extractors.Param.string`, `Extractors.body_text`, `Router.add_exn/compile`, and `Serve.tcp_addr/h1` used by inn.
- Keep Eio resource lifetimes explicit; transport errors are typed results where recoverable, cancellation propagates; do not change another row's WebSocket files.

## Testing Decisions

- The copied router suite and new tests cite each applicable story ID by name. Local TCP tests exercise handler success, keep-alive, bad framing, body bounds and stop/drain without network access outside the test host.
- Run scoped tests, then `dune build @install`, `dune test`, `dune build @fmt` under the required isolated Dune build directory.

## Out of Scope

HTTP/2, server TLS/HTTPS, WebSocket server, runtime factories, domain-policy scheduling, v1 middleware not used by inn or nema, automatic signal handlers, and consumer repository migration.

Scoped verification: `dune build lib/http/eta_http.cma` and `dune test test/http_server` pass in `_build_http_server` (5 server/service cases); row 23 OCaml files formatted.
Integration verification: `dune build @install` currently blocked by concurrent `eta_sql_driver` work; lead owns the full-tree `@install`, `test`, and `@fmt` gates.
