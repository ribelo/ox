---
status: completed
package: eta_ipc
consumer: Pie migration (pienext-pyo6)
---

# A malformed or oversized request gets the service's own error reply

## Problem Statement

`Listener.run` reports decode failures and oversized request lines only through `on_peer_error`; the peer sees the connection close. Pie's control protocol answers `{"error":"malformed-request"}` for both.

## User Stories

1. As a service author, I want `?error_response:(peer_error -> 'response option)` for ingress-side failures (decode, too large, ingress timeout if chosen), encoded and written through normal egress with its bounds, at most once, never for EOF/disconnect, so that a malformed request gets my protocol's error. ^nipc-c871

## Implementation Decisions

- Mirrors `?on_budget_exceeded` (nipc-i5ni); shares its egress path.

## Testing Decisions

- Real sockets: malformed line and oversized line get the reply; no handler admitted; stalled reader hits egress timeout; EOF gets nothing.

Verification: story 1 `^nipc-c871` adds `?error_response` to `Listener.run` and routes decode, over-large and (when the callback chooses) ingress-deadline failures through the existing `respond` egress path; `nix develop -c env DUNE_BUILD_DIR=_build_ipcpr dune build --only-packages eta_ipc,eta,eta_test @install` and `dune build @test/ipc/runtest` passed. The IPC suite is 23 cases, seven new: malformed and overlong lines answered with the chosen reply and no handler admitted, a stalled ingress answered, a declined reply closing silently, the reply byte bound and the egress deadline cutting the error reply, and a disconnected peer never asking for a reply.
Verification: `nix develop -c env DUNE_BUILD_DIR=_build_ipcpr dune build @install`, `dune test` and `dune build @fmt` passed on the whole tree.
