---
status: done
category: enhancement
blocked_by: []
---

# Bind data rather than concatenate SQL

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-8pmk, safe-p1m1, safe-iq5u

**Failure evidence:** Concatenating a supplied name into SELECT text reaches raw SQL as syntax; bound parameters keep that value data.

**Scope:** Trace supported local dynamic concatenation/formatting into authentic raw SQL sinks. Static migrations, compiled query generation and bound parameters remain legal. Do not introduce Source/Code_source nominal APIs or certificate machinery in this lint slice.

**Checks:** Pair a real dynamic SQL sink with the same query using a bound parameter, including a local alias and authentic shadowing. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Measured closure (2026-10-06; counts P/T):** Fresh5587 audit: Pie decided83/99, unknown2/0; Nema135/73, unknown0/3; Exergy189/48, unknown54/7 plus1 nonfile. P/T consumer findings and exclusions0/0 everywhere. Root SQL audit decides all20 sources and emits three production FP at migrate:403,406,408: generic raw forwarding, with structural identifiers escaped by Dsl.quote_ident and values passed separately. Do not rewrite safe migrations. Physical concatenated-name query returns2 rows; bound query returns0. Those historical false positives are now repaired without changing migration SQL: an explicit intact-identifier contract authenticates the genuine internal Dsl.quote_ident compiler UID, retains local helper/alias provenance and refuses same-named counterfeits, quoted/comment contexts and `%S`. The rule is active for prevention; ordinary and audit selection are both asserted, with exact differential controls in the existing corpus. The parent links every site.
