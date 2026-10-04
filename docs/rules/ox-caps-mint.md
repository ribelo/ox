# ox-caps-mint

Story: ^ncapslint-nf4t; evidence: ^ncapslint-w2tq.

Reject references to the raw mint operations in the capability table, not
only applications: taking a dangerous function as a value is access too.
Use the matching Ox_caps wrapper and capability (see [doctrine](<../caps.md>)).

The mandatory source tier uses the compiler parser, resolves lexical opens and
module aliases, and distinguishes local value binders and local modules from
standard-library origins. The typed tier compares normalized compiler paths and
resolves foreign re-exports. Opaque external modules, functor outputs and includes
are accepted source-tier limitations; source rules do not infer their exports or
perform interprocedural analysis. Missing/stale typed evidence is named, never
used as proof of absence. --require-typed makes it a failure.

with_powerbox is allowed only in bin/**/main.ml or an explicitly excluded path.
The Dune dependency and direct Door-module boundaries are checked independently;
the existing nonfatal mint compiler alert is unchanged.

[Violating fixture](<../../test/caps/rules/violating/mint.ml>) and
[clean fixture](<../../test/caps/rules/clean/mint.ml>) form the registry triangle
with this page, checked by --self-check.
