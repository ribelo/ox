---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 16: Restrict cancellation masking around long-lived work

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 15 of 19. File numbering starts after the specification.

**What to build:** A recognised server loop or indefinite wait cannot accidentally be made uninterruptible by a cancellation-protection wrapper.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-ctc4, safe-vj9b, safe-tcqo, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New ox-cancel-mask-scope, complementary to suspending-finalizer enforcement.

## Acceptance criteria

- [ ] Initial matches use resolved protection operations and a finite catalogue of server/indefinite-wait contracts, following supported local calls.
- [ ] Exercise aliasing, a deliberately long-lived protected operation, narrowly protected cleanup and unresolved duration controls.
- [ ] Diagnostics recommend reducing mask scope or changing the interface, not removing protection from cancellation-sensitive cleanup.
- [ ] Runtime cancellation tests use controlled release signals and bounded watchdogs; no permanently hung or sleep-dependent test.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-ctc4: Verify known long-lived operations inside cancellation protection reported; establish that shutdown is not disabled by an over-wide mask.
- safe-vj9b: Verify necessary protected cleanup accepted according to its actual teardown contract; establish that this rule does not contradict suspending-finalizer safety.
- safe-tcqo: Verify indefinite-wait evidence distinguished from unknown duration and ordinary bounded work; establish that the rule neither claims termination proof nor blanket-bans protection.
