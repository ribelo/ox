---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 02: Make best-effort error disposal explicit

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 1 of 19. File numbering starts after the specification.

**What to build:** The gate rejects silent failure disposal through the supported local forms and accepts an explicit, narrow best-effort decision with a checked reason.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-1bc7, safe-s6km, safe-xls8, safe-pufa, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2, safe-vvf8

## Scope and integration

Extend ox-discarded-result; do not register a competing result-discard rule.

## Acceptance criteria

- [ ] Cover direct ignore, wildcard, locally unused named/underscore binding and constant Error-disposal arms; follow ordinary local value aliases where binding identity is known. Unknown higher-order flows are disclosed rather than called handled.
- [ ] An Error arm that recovers or deliberately maps a named error is not equivalent to an unconditional discard. Logging alone does not prove recovery; intentional log-and-continue requires the best-effort decision.
- [ ] Use one expression/binding-scoped exception for one eligible rule with a nonempty reason. Reject wildcard rule lists, unknown IDs, malformed payloads and unused exceptions when the rule is enabled; disabled-rule exceptions are not called stale.
- [ ] Keep rejection of parse failures, stale evidence and invalid imports independent of policy exceptions. No path-wide or capability-rule waiver is introduced.
- [ ] Migrate current named-discard examples and actual Ox sites without changing required failure propagation; verify installed CLI behaviour and reasoned best-effort controls.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-1bc7: Verify ignored results, wildcard bindings and unused named result bindings detected by inferred type and binding identity; establish that adding an underscore does not hide a lost failure.
- safe-s6km: Verify local error-erasing matches and standard result-to-option or result-iteration forms identified as deliberate information-loss decisions; establish that merely matching Error does not count as recovery.
- safe-xls8: Verify propagation, meaningful recovery and a narrowly scoped best-effort exception to be distinct accepted outcomes; establish that legitimate cleanup or optional work does not require invented errors or arbitrary defaults.
- safe-pufa: Verify the exception mechanism restricted to explicitly eligible policy rules, with single-rule reasons and stale-exception checks; establish that it cannot suppress capability, ownership or missing-evidence enforcement.
