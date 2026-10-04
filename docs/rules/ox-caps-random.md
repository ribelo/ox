# ox-caps-random

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

A resolved raw random reference is legal exactly when an enclosing function argument supplies genuine Cap.random authority. Argument authority may be captured by a nested callback or carried in a record, tuple, option, variant or payload. Wrappers obey the same definition; wrapper paths are not exempted.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

The source tier reports naked or argumentless references. Non-wildcard/non-unit parameters may carry authority, so such references defer to typed evidence; source-only success is not proof of genuine token identity. The typed tier follows normalized paths, token identities and argument provenance, not arbitrary opaque higher-order forwarding, dynamic loading or foreign-code behaviour. Missing/stale typed evidence is undecided; --require-typed fails it.

[Violating fixture](<../../test/caps/rules/violating/random.ml>) and
[clean fixture](<../../test/caps/rules/clean/random.ml>) form the rule/fixture/page triangle, checked by --self-check.

Compiled negative fixtures belong to a nested Dune project: the default scan excludes that separate workspace structurally. Explicit sources and annotations are still inspected. Repository tests compile and verify their findings; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).
