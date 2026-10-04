# ox-cancel-safety

A typed, selected interface value must explicitly classify cancellation safety as “safe to re-run”, “unsafe because data is lost” or “unsafe because progress is lost”. Follow the [interface documentation contract](interface-documentation.md) for period-terminated shapes, exemptions and module-default precedence. ^nlintd-vneh ^nlintd-z5p5 ^nlintd-4ja0 ^nlintd-6abn

Never-suspending, non-cancellation-point operations and operations protected throughout are exempt. Partial protection is not a whole-operation exemption. Overriding a default's suspension/cancellation resets its inherited safety claim. The rule checks presence and shape only, **never truth**, and cannot establish retry safety or the absence of side effects. Unknown behaviour belongs in the [individual reason ledger](../issues/ox-lint-docs/triage.md); it remains diagnosable.

Typed evidence: [violating](../../test/lint/violating/cancel_safety.mli), [clean](../../test/lint/clean/cancel_safety.mli), [regression assertions](../../test/lint/test_interface_docs.ml). Build interfaces first; missing fresh compiler evidence is undecided, not exempt.
