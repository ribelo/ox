---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 06: Reject structural comparison of functions

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 5 of 19. File numbering starts after the specification.

**What to build:** Supported structural comparisons whose operands are statically functions fail the gate before they can reach a closure at runtime.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-eeso, safe-doj9, safe-2led, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New narrow typed comparison correctness rule.

## Acceptance criteria

- [ ] Cover standard equality, inequality, ordering and compare at directly known arrow types, with alias/shadowing controls.
- [ ] Diagnostics describe unsupported structural comparison of functions; do not promise that every possible runtime fast path necessarily raises.
- [ ] No advice invents extensional equality for arbitrary functions. Prefer domain IDs or avoid the comparison.
- [ ] Confirm the pinned compiler accepts the violating fixture before lint; do not duplicate an existing compiler diagnostic.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-eeso: Verify resolved standard structural comparison operations on known function operands rejected; establish that a legal type instantiation does not hide a runtime Invalid_argument.
- safe-doj9: Verify physical identity, dedicated comparators and ordinary data equality left alone; establish that this check is not a blanket equality preference.
- safe-2led: Verify containers of closures and unresolved polymorphic operands outside the first analysis horizon named explicitly; establish that the rule does not claim recursive comparability proof.
