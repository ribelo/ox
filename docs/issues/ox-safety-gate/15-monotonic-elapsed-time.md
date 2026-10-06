---
status: done
category: enhancement
blocked_by: []
---

# Use monotonic clocks for elapsed time

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-p9cw, safe-8peq, safe-5a9k

**Failure evidence:** The real ws_client max-timestamp workaround, OTel timing, migration elapsed time and supervised cooldown were corrected to monotonic clocks in Ox; a backward wall jump breaks elapsed arithmetic.

**Scope:** A small operation-specific check: Eio.Time.now, Unix.gettimeofday or Cap_unix.gettimeofday values in paired subtraction/comparison, or sleep/timeout arguments. No general provenance framework; timestamps and scalar-minus-wall civil delays remain legal. Replace elapsed calculations with Mono and Mtime.span.

**Checks:** Pair wall-clock elapsed subtraction/sleep with its monotonic replacement, aliases and authentic shadowing controls. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.

**Measured closure (2026-10-06; counts P/T):** Fresh5587 audit: Pie decided82/99, unknown3/0, findings3/11; Nema135/73, unknown0/3, findings0/0; Exergy189/48, unknown54/7 plus1 nonfile, findings0/0. Exclusions0/0 everywhere. All three production occurrences (Pie text_injection:216,222,227) are one genuine clipboard deadline defect;0 FP. The same file remains opaque at225. Ox elapsed timers were repaired in ab84940; civil delays remain legal (e55ac0e). Remains dormant.
