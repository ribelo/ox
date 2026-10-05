---
status: ready-for-agent
category: enhancement
blocked_by: []
---

# 19: Make retry-safety decisions explicit

**Parent:** [Make unsafe Ox code fail at the strongest available seam](<01-ox-safety-gate.md>)

**Approved slice:** 18 of 19. File numbering starts after the specification.

**What to build:** Identified retryable operations make duplicate-effect risk and recovery explicit rather than treating timeout as proof nothing happened.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Covers:** safe-o2b6, safe-a5mq, safe-3o27, safe-s51t, safe-fr73, safe-y047, safe-czoe, safe-tlyw, safe-m5sp, safe-t37w, safe-12o2

## Scope and integration

Interface-first operation-specific retry policy; no universal idempotency checker.

## Acceptance criteria

- [ ] Inventory existing retry sites and choose one concrete operation whose partial-completion semantics matter; record its replay policy in this ticket before changing the interface.
- [ ] Use an existing policy hook or a narrow operation-specific token/key only when it earns the stated guarantee. A freely constructed boolean named safe is not proof.
- [ ] Deterministic fake operation tests cover failure before commit, effect committed then response lost, duplicate attempt and final error propagation; cancellation still follows Eio.
- [ ] Migrate the selected actual caller and state the remaining scope. A lint check, if needed, checks the explicit contract at named operations rather than inferring idempotency.
- [ ] If no real unsafe retry is found, report that evidence and amend the scoped ticket with the architect; do not invent an operation or mark an unimplemented mechanism delivered.

## Shared acceptance contract

- [ ] Apply the parent specification's rule admission, diagnostic certainty, fresh-evidence and installed-CLI testing contracts. Cite the covered story IDs in tests.
- [ ] Distinguish policy restrictions from demonstrated defects and unverified evidence. Missing evidence cannot be waived or turned into a clean decision.
- [ ] Demonstrate the safe replacement, review real Ox findings, migrate the affected supported sites, and document the finite detection horizon and legitimate counterexamples. Do not activate an unsupported prohibition.
- [ ] Run the repository build, test, formatting and capability/lint gates. Record actual verification and remaining external prerequisites; specification publication is not implementation completion.

## Selected operation and implementation decision

2026-10-05: the concrete operation is Ox_ai.Transport.post_json. Its current loop retries timeouts and transport failures after a POST may have committed remotely; its public contract already admits this ambiguity. The safe default will not authorize replay of ambiguous failures. A separate explicit policy may acknowledge possible duplicate remote effects; this is permission, not inferred idempotency or a deduplication guarantee. Attempt count, backoff and deadline remain separate. Definite-refusal retries require actual operation-contract evidence. Existing provider callers are not mechanically opted in to retain old test expectations.

## Story-specific verification

- safe-o2b6: Verify the policy for an identified non-idempotent retry operation to state when repetition is safe; establish that partial success cannot silently duplicate an external effect.
- safe-a5mq: Verify operation-specific deduplication, reconciliation or refusal of retry used where needed; establish that an HTTP verb, function name or result type is not mistaken for idempotency evidence.
- safe-3o27: Verify timeout-after-commit and partial-success retry tests at an existing operation interface; establish that the policy is verified against the failure window that motivates it.
- safe-s51t: Verify retry budgets and scheduling kept separate from replay safety; establish that adaptive-retry work is neither duplicated nor credited with a guarantee it does not provide.
