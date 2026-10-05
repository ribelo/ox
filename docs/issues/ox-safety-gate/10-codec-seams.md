---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 10: Keep raw representations at explicit codec seams

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 9 of 19. File numbering starts after the specification.

**What to build:** Designated domain interfaces expose meaningful types rather than raw JSON or unchecked runtime values.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-1kqm, safe-gm8y, safe-l2jj, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New designated-interface representation policy, replacing name-based broad-contract heuristics.

## Implementation decision

2026-10-05: designate audited URL, private header-name/value, histogram configuration, logger-limit and redacting-representation contracts by resolved ownership. Do not call the transparent header list validated, or invent schemas for provider-owned protocol payloads. An interface-local `[@@@ox.domain]` opts a consumer into the same bounded representation checks; it adds obligations, never codec exemptions. Codec and extension exceptions remain exact audited value/field positions. Validation claims require the corresponding checked construction evidence; opaque naming alone is not validation.

## Acceptance criteria

- [ ] Inventory and designate domain interfaces and codec seams explicitly in the existing rule policy; scope is not every interface in the ecosystem.
- [ ] Expand manifest aliases where evidence exists; abstract domain types with controlled constructors are accepted. An abstract alias without a validated construction contract is not claimed to validate data.
- [ ] Cover nested published type positions, same-name impostors and JSON-named modules outside the codec policy.
- [ ] Migrate identified Ox interface violations without inventing schemas or hiding required protocol extension points; use roundtrip and invalid-input tests at existing codec interfaces.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-1kqm: Verify designated domain interfaces to use abstract validated types instead of raw JSON or Obj.t; establish that callers cannot bypass the domain model.
- safe-gm8y: Verify real codec and protocol-extension seams explicitly identified by resolved module/value ownership; establish that legitimate raw payload access stays possible without a json-name exemption.
- safe-l2jj: Verify wrapping raw JSON in a transparent alias or renaming a function not to satisfy the policy; establish that the migration earns a real representation guarantee.
