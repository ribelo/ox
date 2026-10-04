# ox-val-behaviour

A typed, selected interface value must have period-terminated Suspension, Cancellation, Finalizers and Locking sentences. Follow the [interface documentation contract](interface-documentation.md) for exact shapes, type families and module-default precedence. ^nlintd-von6 ^nlintd-z5p5 ^nlintd-4ja0 ^nlintd-6abn

The rule checks presence and shape only, **never truth**. Derive claims from implementation and tests. Unknown behaviour is recorded individually in the [reason ledger](../issues/ox-lint-docs/triage.md), not filled in with plausible prose; those gaps still produce diagnostics.

Typed evidence: [violating](../../test/lint/violating/val_behaviour.mli), [clean](../../test/lint/clean/val_behaviour.mli), [regression assertions](../../test/lint/test_interface_docs.ml). Build interfaces first; missing fresh compiler evidence is undecided, not exempt.
