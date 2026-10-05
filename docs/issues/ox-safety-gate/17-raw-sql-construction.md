---
status: implementing
category: enhancement
blocked_by: []
---

# Bind data rather than concatenate SQL

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-8pmk, safe-p1m1, safe-iq5u

**Failure evidence:** Concatenating a supplied name into SELECT text reaches raw SQL as syntax; bound parameters keep that value data.

**Scope:** Trace supported local dynamic concatenation/formatting into authentic raw SQL sinks. Static migrations, compiled query generation and bound parameters remain legal. Do not introduce Source/Code_source nominal APIs or certificate machinery in this lint slice.

**Checks:** Pair a real dynamic SQL sink with the same query using a bound parameter, including a local alias and authentic shadowing. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
