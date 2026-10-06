---
status: done
category: enhancement
blocked_by: []
---

# Reject known blocking calls in Eio

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-9ved, safe-r5ye, safe-ohen

**Failure evidence:** Unix.sleep or Thread.join in an Eio fiber stalls sibling progress; the Counting sibling-owner witness reproduces this scheduling failure.

**Scope:** Check Unix.sleep/sleepf, Thread.delay/join, Domain.join and Semaphore.Counting.acquire in authenticated Eio owner execution. Native workers stay legal. Descriptor I/O is outside this catalogue: no fd-mode inference or general Unix ban, and no duplicate lock rule.

**Checks:** Pair a real Eio callback with a blocking call and the corresponding Eio/native-worker replacement; verify sibling progress without timing sleeps. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Measured closure (2026-10-06; counts P/T):** Fresh5587 shared11+12 audit: Pie decided83/99, unknown2/0; Nema135/72, unknown0/4; Exergy189/48, unknown54/7 plus1 nonfile. P/T findings0/0,0/1,0/0; exclusions0/0 everywhere. Nema test_audit_lifecycle:21 deliberately blocks;22 is an ordinary recursive-horizon unknown. The real sibling-owner semaphore wait times out124; its Eio replacement completes. Remains dormant.
