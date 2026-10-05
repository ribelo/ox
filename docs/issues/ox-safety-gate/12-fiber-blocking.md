---
status: implementing
category: enhancement
blocked_by: []
---

# Reject known blocking calls in Eio

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-9ved, safe-r5ye, safe-ohen

**Failure evidence:** Unix.sleep or Thread.join in an Eio fiber stalls sibling progress; the Counting sibling-owner witness reproduces this scheduling failure.

**Scope:** Check Unix.sleep, proven blocking-fd Unix.read/write, Thread.join and Domain.join in established Eio execution. Native workers and nonblocking fds remain legal. Do not duplicate Stdlib lock-across-suspension checks or ban Unix generally.

**Checks:** Pair a real Eio callback with a blocking call and the corresponding Eio/native-worker replacement; verify sibling progress without timing sleeps. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
