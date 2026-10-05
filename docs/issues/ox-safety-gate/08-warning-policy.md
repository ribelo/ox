---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 08: Protect compiler warning policy

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 7 of 19. File numbering starts after the specification.

**What to build:** An agent cannot quietly weaken the compiler checks on which Ox safety relies.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-tpzm, safe-zua3, safe-zxc1, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New build/source warning-policy checks, adapted to the actual Ox compiler policy.

## Acceptance criteria

- [ ] Derive the required warning set from the pinned compiler and actual repository configuration; do not assume every available warning must be fatal.
- [ ] Inspect supported Dune stanzas and source attributes including alternate spellings and combined/restored sets. Report a scoped policy difference with location.
- [ ] Known targeted exceptions carry an explicit structural policy and reason; blanket all-warning disablement is not accepted by a generic lint waiver.
- [ ] Unsupported templates, profiles or ordered-set evaluation are named unverified for affected policy scope, not silently interpreted as safe. Keep valid equivalent configurations clean.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-tpzm: Verify effective warning and fatal-warning settings compared with Ox policy; establish that equivalent flag spellings and restoration are judged by meaning.
- safe-zua3: Verify source warning attributes and supported Dune compiler flag fields checked with provenance; establish that file-level and build-level opt-outs are equally visible.
- safe-zxc1: Verify justified targeted exceptions distinguished from broad suppression and unknown flag expansion; establish that existing necessary compiler exceptions remain usable without certifying unreadable configuration.
