---
status: done
category: enhancement
blocked_by: []
---

# Reject Eio calls in native workers

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-sr6e, safe-9hbm, safe-eftp

**Failure evidence:** An Ox_blocking.run callback executing Eio.Fiber.yield has no Eio handler on the native thread.

**Scope:** Check callbacks actually invoked by authentic Ox_blocking interfaces, including local aliases/helpers. Completion hooks run in Eio and stay legal. Dormant partial applications stay dormant; omitted effectful optional defaults must not silently pass.

**Checks:** Pair pure native work with a violating Eio call, a missing-pool partial application and an omitted-default control. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Current admission (2026-10-06; P/T):** Pie decided83/99, file unknown2/0; Nema135/73, unknown0/3; Exergy242/48, unknown1/7. Production findings0 throughout. Pie has a stale generated build identity and an unannotated skill_cli interface; Exergy has an unannotated executable plus an unavailable generated-source ownership inventory. These three ordinary production unknown files and the unverified inventory block activation. Nema’s intentional owner-wait test also has an ordinary recursive-horizon unknown at22. The [parent’s current rows](<01-ox-safety-gate.md#execution-context-admission>) retain exact paths, scope and probe evidence. No exclusion or freshness waiver was used; remains dormant. The retained native-yield/owner-wait witnesses still reproduce their failures.
