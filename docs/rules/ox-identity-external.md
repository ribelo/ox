# ox-identity-external

Reject source external declarations backed by `%identity`. The primitive gives the
compiler an unchecked representation claim: compiler acceptance is not evidence that
an abstract type, lifetime or mode conversion is safe. The declaration is the target
even when its argument and result types happen to match. ^safe-9gfb

The rule visits implementation and interface value declarations, including nested
modules, inline includes, module types and functor signatures/bodies. A declaration
reexport that spells the primitive is checked. Aliases and ordinary value reexports
do not create duplicate findings; their original source declaration is checked.
Imported declarations without source are outside this source rule’s evidence scope.

Use a compiler-checked function instead:

```ocaml
let identity value = value
```

Ordinary typed identity, other primitives, comments and strings are clean. There is
no exemption for module names, attributes, documentation claims or alleged trusted
boundaries. The existing `ox-obj-magic` policy and its trust boundary are unchanged.
^safe-4zis ^safe-01za

This is a source rule, not a claim of representation safety inferred from types.
The repository gate still requires fresh compiler evidence; `--require-typed` must
report missing, stale or invalid annotations as evidence errors (exit 2), not clean
results. Findings are exit 1; clean covered input is exit 0. ^safe-tlyw

## Inventory

At baseline `6ee419d6`, the source declaration outside fixtures is
`docs/issues/suspend-token-cost/evidence/nema/shim.ml:3`: `legacy_callback` erases
callback modes. Its comment calls it trusted, but that is not a policy exemption.
It is historical evidence, not a live authority boundary; do not copy it into
application code. The `%identity` string in
`lib/ox_lint/interface_docs.ml:807` is a primitive purity classification, not an
external declaration. No additional trust boundary is introduced. ^safe-4zis
