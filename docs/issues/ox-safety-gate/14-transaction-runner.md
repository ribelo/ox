---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 14: Detect use of the wrong transaction runner

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 13 of 19. File numbering starts after the specification.

**What to build:** A transaction callback does not accidentally send its database work through the originating pool instead of the transaction runner.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-ldtb, safe-j6t8, safe-r1xw, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New ox-transaction-runner with local pool/binder identity tracking.

## Acceptance criteria

- [ ] Cover direct Typed and Raw operations and known aliases inside with_transaction callbacks; resolve the original pool and callback binder rather than comparing names.
- [ ] Independent pools, operations after the callback and use of the provided transaction runner are clean. Deliberate cross-transaction work must cross an explicit reviewed interface, not a generic exception.
- [ ] Opaque helper routing is unverified within the supported transaction context; no interprocedural whole-program guarantee is claimed.
- [ ] Use small pool and rollback fixtures with deterministic completion, avoiding a hanging test to demonstrate the misuse.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-ldtb: Verify operations on the originating pool inside its transaction callback reported; establish that intended transactional work does not execute outside the transaction or wait for another connection.
- safe-j6t8: Verify local aliases of that pool detected while the transaction runner and independent pools are accepted; establish that spelling changes neither evade the rule nor create false positives.
- safe-r1xw: Verify corrected code demonstrated through commit and rollback outcomes at the public SQL interface; establish that the rule protects actual transaction semantics.
