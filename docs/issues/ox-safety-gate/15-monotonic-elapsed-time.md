---
status: implementing
category: enhancement
blocked_by: []
---

# Use monotonic clocks for elapsed time

**Parent:** [Concrete Eio/Ox safety gate](<01-ox-safety-gate.md>) · **Stories:** safe-p9cw, safe-8peq, safe-5a9k

**Failure evidence:** The real ws_client max-timestamp workaround, OTel timing, migration elapsed time and supervised cooldown were corrected to monotonic clocks in Ox; a backward wall jump breaks elapsed arithmetic.

**Scope:** A small operation-specific check: Eio.Time.now, Unix.gettimeofday or Cap_unix.gettimeofday values in paired subtraction/comparison, or sleep/timeout arguments. No general provenance framework; timestamps and scalar-minus-wall civil delays remain legal. Replace elapsed calculations with Mono and Mtime.span.

**Checks:** Pair wall-clock elapsed subtraction/sleep with its monotonic replacement, aliases and authentic shadowing controls. Fresh three-consumer counts and production-finding classification are required before activation; the parent defines the compact completion test.
