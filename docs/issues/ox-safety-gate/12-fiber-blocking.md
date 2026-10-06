---
status: implementing
category: enhancement
blocked_by: []
---

# Reject known blocking calls in Eio

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-9ved, safe-r5ye, safe-ohen

**Failure evidence:** Unix.sleep or Thread.join in an Eio fiber stalls sibling progress; the Counting sibling-owner witness reproduces this scheduling failure.

**Scope:** Check Unix.sleep/sleepf, Thread.delay/join, Domain.join and Semaphore.Counting.acquire in authenticated Eio owner execution. Native workers stay legal. Descriptor I/O is outside this catalogue: no fd-mode inference or general Unix ban, and no duplicate lock rule.

**Checks:** Pair a real Eio callback with a blocking call and the corresponding Eio/native-worker replacement; verify sibling progress without timing sleeps. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
