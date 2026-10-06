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

**Measured closure (2026-10-06; counts P/T):** Fresh5587 shared11+12 audit: Pie decided83/99, unknown2/0; Nema135/72, unknown0/4; Exergy189/48, unknown54/7 plus1 nonfile. P/T findings0/0,0/1,0/0; exclusions0/0 everywhere. The Nema finding is an intentional owner-thread test wait, not a native-worker or production defect. The native Eio.Fiber.yield witness raises Effect.Unhandled; the pure native replacement succeeds. Remains dormant, with exact ledger in the parent.
