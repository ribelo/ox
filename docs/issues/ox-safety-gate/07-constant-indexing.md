---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 07: Reject provably out-of-bounds constant indexing

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 6 of 19. File numbering starts after the specification.

**What to build:** A provably invalid literal index into a known literal collection fails with its actual bounds, without guessing dynamic sizes.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-rxya, safe-d197, safe-xd2e, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New bounded constant-index correctness rule.

## Acceptance criteria

- [ ] Use resolved standard getters and typed literals; no textual operator fallback. Cover zero length, -1, length-1 and length.
- [ ] String lengths use decoded bytes, not source character counts. Add bytes only when its origin and length are proved by the supported local form.
- [ ] Fixtures separate constant violations, valid indexing, shadowed operations and unknown lengths; document the finite horizon.
- [ ] No general bounds solver or whole-program range analysis is introduced.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-rxya: Verify constant out-of-range indexes into supported literal arrays and strings detected; establish that an obvious runtime bounds failure does not survive compilation.
- safe-d197: Verify decoded literal length, negative indexes and the exact upper bound handled correctly; establish that escapes and byte indexing do not cause false claims.
- safe-xd2e: Verify dynamic lengths and user-defined indexing left outside the first rule unless resolved evidence establishes their contract; establish that source spelling is never treated as semantic proof.
