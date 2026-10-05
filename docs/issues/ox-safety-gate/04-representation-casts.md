---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 04: Close unchecked representation-cast bypasses

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 3 of 19. File numbering starts after the specification.

**What to build:** An external representation claim cannot silently bypass the typed interface or capability restrictions.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-9gfb, safe-4zis, safe-01za, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

Add an identity-external policy beside existing Obj.magic enforcement; reuse cast policy rather than duplicate its findings.

The concrete local-callback operations in the existing Once owner are an explicit trusted-seam candidate, not a naming exemption. Their private locality primitive and affine adaptation require fresh peer interfaces, current compiler fingerprints, resolved operator identities and complete implementation verification. The proposed heap-guarded locality erasure is rejected: a joined Eio lifetime does not establish collector roots for local captures during pre-entry suspension. Any replacement must prove that runtime invariant independently; structural source pins alone are insufficient. The global-once adapter and directly called local callbacks do not require this locality erasure. Only the proven declaration/expression is admitted. Candidate naming may demand that proof but cannot grant it; missing evidence stays unverified and ordinary primitive declarations retain source-level rejection (safe-4zis).

## Acceptance criteria

- [ ] Cover primitive declarations, interface exposure and supported re-exports; retain existing Obj.magic restrictions without reporting one occurrence twice.
- [ ] Inventory actual legitimate sites before defining any trusted structural seam. Ship no blanket directory or naming exemption and no general local waiver for type-safety bypasses.
- [ ] The diagnostic describes an unchecked representation claim, not a proof of memory corruption. A foreign C primitive is not advertised as a safe replacement.
- [ ] Exercise installed-gate acceptance of an ordinary typed identity and rejection of an untrusted primitive declaration.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-9gfb: Verify external declarations using the identity primitive inspected in implementation and interface forms; establish that a different spelling of an unchecked cast does not evade the gate.
- safe-4zis: Verify legitimate representation primitives confined to an explicit trusted implementation contract with a tested invariant; establish that ordinary application code cannot acquire a cast exception by naming a module Unsafe.
- safe-01za: Verify an ordinary typed identity or stronger representation offered as the replacement; establish that changing the external primitive name is not mistaken for fixing the unsafe operation.
