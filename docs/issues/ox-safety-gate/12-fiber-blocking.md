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

**Current admission (2026-10-06; P/T):** Pie decided83/99, file unknown2/0; Nema135/73, unknown0/3; Exergy242/48, unknown1/7. Production findings0 throughout. Pie has a stale generated build identity and an unannotated skill_cli interface; Exergy has an unannotated executable plus an unavailable generated-source ownership inventory. These three ordinary production unknown files and the unverified inventory block activation. Nema’s intentional owner-wait test also has an ordinary recursive-horizon unknown at22. The [parent’s current rows](<01-ox-safety-gate.md#execution-context-admission>) retain exact paths, scope and probe evidence. No exclusion or freshness waiver was used; remains dormant. The retained native-yield/owner-wait witnesses still reproduce their failures.
