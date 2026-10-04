# ox-public-exception

Story: ^nlintc-7be1; evidence: ^nlintc-kdcl.

## Definition

An exception declared inside a module-type contract is legal: a functor requires that constructor from its backend, rather than publishing a package-owned exception API. An exception in the interface of a module listed in its owning Dune stanza's `private_modules` is also legal: that build-declared module is not part of the published package API. Package-published exception declarations, including constructors inside ordinary nested module signatures and exception rebindings, are rejected in interfaces. Prefer result-returning boundaries; keep implementation defects private.

The shipped allowance registry is empty. No interface pathname receives special treatment. Module-type contracts and build-declared private modules are accepted structurally, not through allowances. The rule applies to .mli source interfaces, not private declarations in implementations.

## Accepted false negatives

This syntax-only tier does not expand includes or aliased module types to discover constructors they expose. It does not infer implementation exports without explicit interfaces and performs no cross-unit API analysis. An accepted module-type constructor does not prove its runtime exception use is correct; it proves the declaration is a required contract rather than a published package-owned constructor.

## Evidence

[Violating fixture](<../../test/lint/violating/public_exception.mli>) and [clean fixture](<../../test/lint/clean/public_exception.mli>) are checked by [exact-site tests](<../../test/lint/test_concurrency.ml>). The registry keeps the rule/fixture/page triangle.

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
