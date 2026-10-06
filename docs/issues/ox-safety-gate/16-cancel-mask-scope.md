---
status: done
category: enhancement
blocked_by: []
---

# Keep long-lived work cancellable

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-ctc4, safe-vj9b, safe-tcqo

**Failure evidence:** Eio.Cancel.protect around await_cancel or a server without a stop path prevents shutdown from reaching the protected work.

**Scope:** Report the narrow known indefinite-operation catalogue under protection. Account for effective inner deadlines and nested shields. Accept bounded cleanup; do not certify termination, opaque callback latency, stream protocols or physical settlement.

**Checks:** Pair shielded indefinite work with unshielded work and a genuine inner finite deadline; preserve cancellation behaviour. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Measured closure (2026-10-06; counts P/T):** Fresh5587 audit: Pie decided83/99, unknown2/0; Nema135/73, unknown0/3; Exergy189/48, unknown54/7 plus1 nonfile. P/T findings and exclusions0/0 everywhere; no production findings to classify. Protected indefinite waiting times out124; bounded/unshielded replacement completes. Unsaturated servers do not execute. This physical failure justifies retention, not a termination proof. Remains dormant.
