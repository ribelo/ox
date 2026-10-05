---
status: implementing
category: enhancement
blocked_by: []
---

# Reject Eio calls in native workers

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-sr6e, safe-9hbm, safe-eftp

**Failure evidence:** An Ox_blocking.run callback executing Eio.Fiber.yield has no Eio handler on the native thread.

**Scope:** Check callbacks actually invoked by authentic Ox_blocking interfaces, including local aliases/helpers. Completion hooks run in Eio and stay legal. Dormant partial applications stay dormant; omitted effectful optional defaults must not silently pass.

**Checks:** Pair pure native work with a violating Eio call, a missing-pool partial application and an omitted-default control. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
