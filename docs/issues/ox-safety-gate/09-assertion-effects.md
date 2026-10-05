---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 09: Keep required work outside assertions

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 8 of 19. File numbering starts after the specification.

**What to build:** Supported writes and effectful calls required by the program do not disappear when assertions are disabled.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-pcom, safe-u7cx, safe-28t6, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New assertion-side-effect check with an explicit finite effect horizon.

## Acceptance criteria

- [ ] Begin with direct mutation, resolved known effectful calls and supported local helpers; document propagation limits. Reuse existing effect evidence only where its semantics establish the relevant write/I/O fact.
- [ ] Include a sequence of pure expressions as a clean control and a single effectful predicate call as a violating case.
- [ ] An opaque call is not assumed pure. Distinguish unknown evidence from an actual effect diagnostic.
- [ ] Compile paired normal and noassert runtime fixtures; required side effects survive in the corrected form without converting input validation into a removable assertion.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-pcom: Verify known mutation and required I/O inside assertion conditions detected; establish that a release build does not omit work on which the program depends.
- safe-u7cx: Verify effect-free sequences accepted and unresolved assertion calls named unverified within the declared rule scope; establish that sequencing is not confused with proof of effects.
- safe-28t6: Verify repaired code checked with and without assertions; establish that moving required work outside the assertion preserves ordinary failure behaviour.
