# ox-caps-signature

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

Every dangerous raw reference must have the matching genuine abstract-token capability in an enclosing function argument. Wrapper calls additionally require their capability payload to come from an argument, rather than an ambient or locally minted value. Raw operations and wrappers share this decision.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

The source tier reports naked or argumentless references. Non-wildcard/non-unit parameters may carry authority, so such references defer to typed evidence; source-only success is not proof of genuine token identity. The typed tier follows normalized paths, token identities and argument provenance, not arbitrary opaque higher-order forwarding, dynamic loading or foreign-code behaviour. Missing/stale typed evidence is undecided; --require-typed fails it.

[Violating fixture](<../../test/caps/rules/violating/signature.ml>) and
[clean fixture](<../../test/caps/rules/clean/signature.ml>) form the rule/fixture/page triangle, checked by --self-check.
