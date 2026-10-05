---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 13: Enforce callback behavioural contracts

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 12 of 19. File numbering starts after the specification.

**What to build:** A designated callback cannot silently violate its documented no-raise, no-suspend or non-re-entry contract.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-vske, safe-0ozq, safe-055u, safe-18ht, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New ox-callback-contract for explicit callback-position obligations.

## Acceptance criteria

- [ ] Initial no-raise positions include blocking cancellation and settled hooks where their actual interface contract forbids raising; no-suspend positions must have an actual strict contract.
- [ ] Use a finite local call horizon with resolved identities and distinguish handled raises from escaping raises where the supported analysis proves it.
- [ ] For same-pool shutdown, trace the run pool and locally captured shutdown receiver; independent pools and shutdown after physical completion are clean controls.
- [ ] Reuse existing interface behaviour summaries where sound. A new shared helper is introduced only when repeated concrete analysis requires it; no generic effect-analysis platform ticket.
- [ ] Runtime public-interface tests retain documented propagation of defects when an unverified callback violates its contract; lint does not replace runtime semantics.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-vske: Verify direct known raises in a no-raise callback and known suspension in a no-suspend callback rejected; establish that a plain function type does not hide these obligations.
- safe-0ozq: Verify shutdown of the same pool from its own running callback detected in supported local identity flows; establish that a callback does not wait for its own completion.
- safe-055u: Verify callback contracts stated per parameter and unknown helper behaviour disclosed; establish that return type or prose naming does not manufacture a behavioural guarantee.
- safe-18ht: Verify must-not-suspend-for-long distinguished from never-suspends and expected defects preserved outside designated callback restrictions; establish that lint does not outlaw normal result-function defects or invent a static latency proof.
