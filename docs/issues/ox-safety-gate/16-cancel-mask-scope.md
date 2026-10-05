---
status: implementing
category: enhancement
blocked_by: []
---

# Keep long-lived work cancellable

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-ctc4, safe-vj9b, safe-tcqo

**Failure evidence:** Eio.Cancel.protect around await_cancel or a server without a stop path prevents shutdown from reaching the protected work.

**Scope:** Report the narrow known indefinite-operation catalogue under protection. Account for effective inner deadlines and nested shields. Accept bounded cleanup; do not certify termination, opaque callback latency, stream protocols or physical settlement.

**Checks:** Pair shielded indefinite work with unshielded work and a genuine inner finite deadline; preserve cancellation behaviour. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
