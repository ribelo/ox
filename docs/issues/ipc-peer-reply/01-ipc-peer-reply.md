---
status: ready-for-agent
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
