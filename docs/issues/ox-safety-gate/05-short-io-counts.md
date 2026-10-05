---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 05: Require handling of short I/O counts

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 4 of 19. File numbering starts after the specification.

**What to build:** A caller cannot discard the amount actually transferred by a supported read or write and assume complete transfer.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-jwwj, safe-qmcw, safe-t50j, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

New short-I/O outcome rule using resolved operation contracts, including capability wrappers.

## Acceptance criteria

- [ ] Initial sink shapes include ignore, wildcard and locally unused named bindings, using actual callee identity and result shape; known wrappers preserve the operation contract.
- [ ] Handle tuple-returning operations by tracking the count component only where the contract supports it. Unknown wrappers are not classified solely by name.
- [ ] For stream transfer, test short counts, EOF, zero progress and error preservation. Datagram operations must not receive a generic loop-until-full recommendation.
- [ ] Reuse existing complete-transfer operations; add a narrow wrapper only for a demonstrated caller gap and test it through its public interface. No generic I/O framework.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-jwwj: Verify discarded byte counts from supported native and capability-wrapper operations reported; establish that short transfers cannot silently truncate or corrupt a message.
- safe-qmcw: Verify a caller to handle partial transfer, EOF and zero progress or select an existing complete-transfer interface; establish that binding a count without using it is not sufficient.
- safe-t50j: Verify stream and datagram semantics kept distinct and the operation table tested; establish that the suggested repair does not split a datagram or spin forever.
