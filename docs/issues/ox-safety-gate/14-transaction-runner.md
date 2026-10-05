---
status: implementing
category: enhancement
blocked_by: []
---

# Use the transaction runner

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-ldtb, safe-j6t8, safe-r1xw

**Failure evidence:** dc803f06 binds real transaction provenance: pool.exec inside that pool's transaction can escape its connection or wait for another connection rather than use the callback runner.

**Scope:** Keep the built typed rule for originating-pool operations inside its transaction callback; follow local aliases. The runner and distinct pools remain legal.

**Checks:** Keep public commit/rollback tests. Add one clean/violating consumer-style pair only if the existing fixtures lack it. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
