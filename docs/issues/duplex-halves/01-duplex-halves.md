---
status: ready
package: ox_http
consumer: every consumer (Ox-internal; ADR-0010)
---

# Duplex flows split into owned reader and writer halves

## Problem Statement

Row 57 found two fibers reading and writing one TLS connection through one ciphertext buffer; the fix is three mutexes and a discipline (`tls_flow.ml` `read_mu`, `write_mu`, `ssl_mu`). Nothing stops the next change from sharing a buffer again. The WebSocket keepalive and receive loops are the same shape.

## Solution

A duplex flow splits once into a `reader @ unique` and a `writer @ unique`, each owning its own buffer; each half is moved into one fiber with `once-forks`'s `Scope.fork`. Two fibers holding the same half does not typecheck, so the buffer mutexes disappear. OpenSSL's `SSL*` really is shared by both directions and keeps `ssl_mu`.

## User Stories

1. As a transport author, I want `Tls_flow.split : t @ unique -> reader @ unique * writer @ unique`, `read : reader @ unique -> Cstruct.t -> int * reader @ unique` and `write : writer @ unique -> Cstruct.t -> writer @ unique`, so that one half has one owner. ^nduplex-87sz
2. As a transport author, I want `Ws_client` built on the halves: the receive loop owns the reader, one writer fiber owns the writer and serializes pings, pongs and user frames through a `Channel`, so that the keepalive cannot interleave with a user write by construction. ^nduplex-nu1d
3. As a kernel maintainer, I want `read_mu` and `write_mu` removed from `Tls_flow` and `ssl_mu` kept with a comment naming the shared `SSL*`, so that every remaining lock guards something actually shared. ^nduplex-6d16
4. As a kernel maintainer, I want the row-57 regression (`wsduplex-j4rn`) kept as a runtime test and joined by a compile-fail case (one writer in two fibers), so that the class is refused before the test runs. ^nduplex-s3t9
5. As a kernel maintainer, I want the 30 s keepalive flood in `@stress` and the Pie long-recording path measured before and after, the halves rebuilt per write or threaded through a module-private `Obj.magic_unique`, whichever is within noise, so that safety costs no throughput. ^nduplex-akjv

## Implementation Decisions

Depends on `once-forks` (moving a unique half into a fiber). The consuming close comes from `owned-handles` as restated on 2026-11-03: `close_reader : reader @ unique -> unit` and `close_writer : writer @ unique -> (unit, error) result` consume their half, and `Ws_client.close` consumes the writer it owns (^nown-ubbv). A half closed by its owner ends its direction; the flow closes when both halves are closed (a shared close counter inside the `SSL*` holder).

## Testing Decisions

`test/http` ws and tls suites, the compile-fail case, `@stress` ws keepalive flood and half-close storm.

## Out of Scope

HTTP/1 server connections (one fiber per connection; no duplex sharing today).
