---
status: ready-for-agent
category: enhancement
blocked_by:
  - "[[docs/issues/once-forks/01-once-forks]]"
  - "[[docs/issues/owned-handles/01-owned-handles]]"
  - "[[docs/issues/spawner/01-spawner]]"
  - "[[docs/issues/ox-mutex/01-ox-mutex]]"
  - "[[docs/issues/parse-dont-validate/01-parse-dont-validate]]"
---

# 20: Close bypasses after safe interfaces exist

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 19 of 19. File numbering starts after the specification.

**What to build:** Safe concurrency, ownership and bounded-value interfaces become mandatory only where their replacements are delivered and verified.

**Blocked by:** [once-forks](<../once-forks/01-once-forks.md>) (existing delivery; applicable guarantees must be verified); [owned-handles](<../owned-handles/01-owned-handles.md>) (existing delivery; applicable guarantees must be verified); [spawner](<../spawner/01-spawner.md>) (existing delivery; applicable guarantees must be verified); [ox-mutex](<../ox-mutex/01-ox-mutex.md>) (existing delivery; applicable guarantees must be verified); [parse-dont-validate](<../parse-dont-validate/01-parse-dont-validate.md>) (existing delivery; applicable guarantees must be verified)

**Status:** ready-for-agent

**Covers:** safe-vaz6, safe-6ukl, safe-u2na, safe-8o0p, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

Activate and extend existing bypass enforcement only after its public replacements and migration evidence exist.

## Acceptance criteria

- [ ] Prerequisites are the existing once-forks, owned-handles, spawner, ox-mutex and parse-dont-validate deliveries for the matching surfaces. Do not depend on the old raw-concurrency ticket as a whole if that would duplicate or cycle with this activation slice.
- [ ] Use the current dormant-rule policy as the starting point. Read actual delivered interfaces and migration evidence, not just delivery-map checkboxes, before changing applicability.
- [ ] Close relevant raw calls and legacy constructor routes at honest structural seams. A broad kernel-only boundary is not assumed correct for other Ox adapters.
- [ ] Validate directly compiled consumer examples and real consumer migration evidence. Keep unsupported surfaces explicitly dormant; completing only a subset is not completion of the whole ticket.
- [ ] Local-scope, suspend-token, duplex-halves and related work become blockers only for a guarantee this activation actually claims. Add those exact edges before expanding its scope.
- [ ] Keep this ticket a bounded gate-policy/activation change: prerequisite API work and large consumer migrations remain in their existing specs or separately approved child tickets.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-vaz6: Verify raw-concurrency enforcement activated only after once-taking forks, a Spawner and guarded access exist and applicable callers have migrated; establish that the compiler guarantees cannot be bypassed but no unavailable interface is demanded.
- safe-6ukl: Verify ownership and validated capacity, concurrency and byte-limit guarantees inherited from their existing deliveries; establish that this work closes legacy escape routes instead of duplicating their implementations.
- safe-u2na: Verify each activation backed by a compile-fail control, a clean public-interface control and installed-gate coverage; establish that dormant or unverified surfaces are never advertised as enforced.
- safe-8o0p: Verify each consumer or additional lifetime/suspension prerequisite recorded before activation and any wide migration sequenced expand, migrate, contract; establish that each committed slice stays verifiable without swallowing unrelated work.
