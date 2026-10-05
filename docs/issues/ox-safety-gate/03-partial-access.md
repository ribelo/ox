---
status: ready-for-agent
category: enhancement
blocked_by:
  - "[[02-explicit-error-disposal]]"
---

# 03: Replace unchecked option and list extraction

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 2 of 19. File numbering starts after the specification.

**What to build:** Ordinary callers cannot silently extract absent values; internal invariants are explicit rather than disguised as fallback values.

**Blocked by:** [02: Make best-effort error disposal explicit](<02-explicit-error-disposal.md>)

**Status:** ready-for-agent

**Covers:** safe-7t06, safe-bguw, safe-35sb, safe-3osb, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2, safe-vvf8

## Scope and integration

New partial-access policy checks, adapted from Elenchus rather than copied as a dependency.

## Acceptance criteria

- [ ] Initial operations are Option.get, List.hd and List.tl on their actual standard-library identities. State explicitly that use is a policy finding, not proof the argument is empty.
- [ ] Review OTel ending/deadline extraction, TLS error decoding and joined concurrency result collection as initial call-site families; prefer returning transition evidence or matching once.
- [ ] No mechanical rewrite to assert false, failwith or an arbitrary default counts as remediation. Legitimate internal invariants use ticket 1 exception discipline.
- [ ] Compile both violating and correct forms, including local name shadowing, and run affected public-interface regression tests.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-7t06: Verify calls to the standard partial option and list accessors identified through resolved identities; establish that aliases and opens do not hide partiality and similarly named user functions are not accused.
- safe-bguw: Verify affected state transitions and error decoding rewritten to return or bind the required value; establish that callers do not reconstruct a mutation-dependent invariant or evaluate a decoder twice.
- safe-35sb: Verify genuine joined-fiber or representation invariants to have a narrow reasoned exception; establish that the rule does not replace one proof obligation with an assertion or fabricated default.
- safe-3osb: Verify migration tests to preserve empty-case and failure behaviour; establish that lint cleanup does not convert a defect into apparent success.
