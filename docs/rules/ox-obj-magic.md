# ox-obj-magic

Story: ^nlintc-7be1; evidence: ^nlintc-kdcl.

The typed tier refuses every value named `magic*` originating in `Stdlib.Obj`,
including OxCaml's `Obj.magic_portable`. Module aliases/opens are resolved;
a user module merely named Obj is not the unsafe Stdlib module. Replace casts
with a typed representation.

The sole exact allowance is `lib/ox/once.ml`, reserved for the trusted ownership
casts of row 61. **That file does not yet exist**. No other file or directory is
allowed. Violating fixtures deliberately contain unsafe calls; fixture deciders
are tested directly, not excused by a production allowance.

**Accepted false negatives.** Value aliases and user wrappers around Obj casts
are not followed. This rule is not a proof of memory or mode safety: other Obj
operations, C stubs and custom unchecked primitives are outside its set.

## Evidence

[Violating fixture](<../../test/lint/violating/obj_magic.ml>) and
[clean fixture](<../../test/lint/clean/obj_magic.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.
