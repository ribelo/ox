---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 15: Use monotonic time for elapsed-time decisions

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 14 of 19. File numbering starts after the specification.

**What to build:** Supported elapsed-time decisions use monotonic clocks while timestamps and calendar scheduling preserve wall-clock meaning.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-p9cw, safe-8peq, safe-5a9k, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New ox-monotonic-elapsed-time; do not duplicate ox-race-deadline.

## Acceptance criteria

- [ ] Start with named operation contracts and direct local wall-clock-to-elapsed flows; generic float arithmetic and opaque provenance are not automatically violations.
- [ ] Keep calendar deadlines, logging timestamps and explicit conversions with a defined contract as clean controls.
- [ ] Reuse monotonic-timeout delivery rather than reimplement timeout. If an additional operation needs a monotonic interface, add only that narrow interface and its tests before enforcing it.
- [ ] Use virtual wall-clock jumps with monotonic elapsed controls; ensure cancellation and existing result behaviour remain unchanged.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-p9cw: Verify known wall-clock values reaching designated elapsed-time, local deadline or refill calculations reported; establish that clock corrections do not distort these decisions.
- safe-8peq: Verify timestamp and duration provenance distinguished through typed interfaces or supported local flow rather than variable names; establish that legitimate calendar operations are not rewritten.
- safe-5a9k: Verify the existing monotonic timeout and clock interfaces used as replacements and verified under clock jumps; establish that a lint fix changes the clock semantics intentionally.
