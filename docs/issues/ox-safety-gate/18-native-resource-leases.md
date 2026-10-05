---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 18: Retain native resources until physical completion

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 17 of 19. File numbering starts after the specification.

**What to build:** An owner may stop waiting, but buffers and handles used by admitted native work remain retained until that work physically settles.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-zgfv, safe-sw86, safe-bt9f, safe-m6vf, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

Interface-first safety slice; only add bypass checks once the lease contract exists.

## Acceptance criteria

- [ ] Choose the smallest existing native handle/buffer user that crosses waiter cancellation. Add an opaque lease/owner operation at that existing seam, not a new runtime or mandatory wrapper around pure native jobs.
- [ ] Exercise cancellation before claim (including no on_settled callback), after claim, timeout, normal return, native exception and admission rejection; each releases its retained ownership exactly once.
- [ ] On-settled hooks run in the documented Eio owner context. A detached waiter does not authorize resource release; the completion path must retain ownership independently.
- [ ] Keep outstanding worker ownership explicit under both Drain and Detach_started. Document the limits of affine modes: they do not prove that a value must be used or closed.
- [ ] Add a scoped bypass restriction only for the migrated interface after its replacement works. If the real-user inventory requires a larger signature migration, publish sized expand/migrate/contract child work before widening this ticket.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Story-specific verification

- safe-zgfv: Verify an explicit lease retaining callback resources through physical completion; establish that waiter timeout or cancellation cannot release a resource still in use.
- safe-sw86: Verify cancellation before claim, submission rejection and physical completion to release the retained ownership exactly once through the correct owner context; establish that resources neither leak nor close early.
- safe-bt9f: Verify Drain, detach policy and settlement failures accounted for without adding a second cancellation model; establish that Eio still owns interruption and native completion remains truthful.
- safe-m6vf: Verify one demonstrated native-resource user migrated and the remaining bypass inventory explicit; establish that the interface is verified by a real use rather than a hypothetical generic leasing framework.
