---
status: done
category: enhancement
blocked_by: []
---

# Use the transaction runner

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-ldtb, safe-j6t8, safe-r1xw

**Failure evidence:** dc803f06 binds real transaction provenance: pool.exec inside that pool's transaction can escape its connection or wait for another connection rather than use the callback runner.

**Scope:** Keep the built typed rule for originating-pool operations inside its transaction callback; follow local aliases. The runner and distinct pools remain legal.

**Checks:** One clean/violating pair and one MI-first exact corpus. A real size-one SQLite pool blocks when its transaction callback re-borrows the originating pool (bounded subprocess requires timeout124); using the callback runner preserves the committed row, returns the primary error, and rolls back the second insertion. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Measured closure (2026-10-06; counts P/T):** Fresh5587 audit: Pie decided83/99, unknown2/0; Nema135/73, unknown0/3; Exergy189/48, unknown54/7 plus1 nonfile. P/T findings and exclusions0/0 everywhere; no production findings to classify. The size-one pool timeout124 and successful runner commit/rollback justify retention despite zero consumer findings. Remains dormant.
