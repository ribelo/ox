# ox-obj-magic

Story: ^nlintc-7be1; evidence: ^nlintc-kdcl.

The typed tier refuses every value named `magic*` originating in `Stdlib.Obj`,
including OxCaml's `Obj.magic_portable`. Module aliases/opens are resolved;
a user module merely named Obj is not the unsafe Stdlib module. Replace casts
with a typed representation.

One finite primitive is shipped for ^nonce-ldtz and ^nonce-mjpe: the single physical
`Obj.magic_many` identifier in the seven-line **global** atomic guard in
[Once](<../../lib/ox/once.ml>). The source and authored public interface digests,
fresh CMT/CMti/current-CMI import fingerprints, canonical public export UID and
compiler-native global-once/global-many ABI must agree. The complete emitted body
must permanently claim `Atomic.exchange used true` before caller code, reject
repeat entry, and never reset the claim. Canonical Stdlib identities are checked.
A missing or contradictory peer is undecided and the cast remains a finding.
A matching name, path, line or clone does not grant admission: only the proven
physical expression object is exempt. The legacy factory still reports that cast.

No `%identity` primitive, local-to-global bridge or Eio provider is exempt. Global
closures are GC-markable; source pins do not establish safety for a closure
capturing local allocation. Ordinary consumer casts and extra casts in an
unreviewed implementation retain their findings. Violating fixtures are checked
directly, not excused by a production allowance.

**Accepted false negatives.** Value aliases and user wrappers around Obj casts
are not followed. This rule is not a proof of memory or mode safety: other Obj
operations, C stubs and custom unchecked primitives are outside its set.

## Evidence

[Violating fixture](<../../test/lint/violating/obj_magic.ml>) and
[clean fixture](<../../test/lint/clean/obj_magic.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
