---
status: completed
package: ox_http
consumer: every consumer (Ox-internal; ADR-0010)
---

# Duplex flows split into owned reader and writer halves

> Completed 2026-11-03 as restated below. Verified: `Tls_flow`'s inbound, outbound and SSL state branded by their `Ox.Mutex` locks, the `test/http` TLS and WebSocket suites (wsduplex-j4rn included) and the `bad_tls_wrong_lock` refusal pass; `bench/tls_duplex.exe 128` gave 437-509 MiB/s per direction before and 543-555 after (five runs each, loopback, heisenbug).

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

## Restated 2026-11-03

Splitting does not remove the locks, because OpenSSL crosses directions. A read can leave output for the peer that must be flushed (`try_flush` in `tls_flow.ml`), and a write can return `WANT_READ` and need inbound ciphertext fed first. A reader half and a writer half that each own one buffer would have to hand that work to each other through new cross-fiber wake-ups, which is the class of bug Ox has had most (`stress`). The halves would also have to exist for plain `ws://` flows, and `Ws_client` would need two internal fibers and a channel per connection.

The row-57 class is "a buffer reached without the lock that owns it". `Ox.Mutex` (`ox-mutex`) refuses that class at compile time without a split: `Tls_flow`'s inbound buffer and record-boundary state take the brand of `read_mu`, the outbound buffer the brand of `write_mu`, and the `SSL*` the brand of `ssl_mu`, each reachable only through operations that require the matching access. The locks stay. Every access to the state is then typed by its lock.

Stories therefore change: story 1 becomes the branded state of `Tls_flow` (^nduplex-87sz); story 3 keeps all three locks, each now guarding a branded datum (^nduplex-6d16); story 4's compile-fail case is a buffer reached without its lock or under the other lock (^nduplex-s3t9); story 5 measures the keepalive flood before and after (^nduplex-akjv). Story 2 (`Ws_client` on halves and a writer fiber) is withdrawn: `Ws_client`'s own state already has one lock (`lock`), and the TLS state under it is the part that shared a buffer (^nduplex-nu1d). The consuming-close note above does not apply without halves; close stays idempotent.

## Testing Decisions

`test/http` ws and tls suites, the compile-fail case, `@stress` ws keepalive flood and half-close storm.

## Out of Scope

HTTP/1 server connections (one fiber per connection; no duplex sharing today).
