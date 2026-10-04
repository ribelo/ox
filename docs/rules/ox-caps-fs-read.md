# ox-caps-fs-read

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

A resolved raw fs-read reference is legal exactly when an enclosing function argument supplies genuine Cap.fs_read authority. Argument authority may be captured by a nested callback or carried in a record, tuple, option, variant or payload. Wrappers obey the same definition; wrapper paths are not exempted.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

The source tier reports naked or argumentless references. Non-wildcard/non-unit parameters may carry authority, so such references defer to typed evidence; source-only success is not proof of genuine token identity. The typed tier follows normalized paths, token identities and argument provenance, not arbitrary opaque higher-order forwarding, dynamic loading or foreign-code behaviour. Missing/stale typed evidence is undecided; --require-typed fails it. Metadata queries (Sys.file_exists, Unix.stat, Unix.realpath) are not named raw targets, but APIs doing filesystem reads still explicitly declare fs_read. `Unix.dup` and `dup2` are deliberately not filesystem-read targets: they operate on descriptors already held, not filesystem paths. See the descriptor-possession decision in [ox-caps-fs-write](<ox-caps-fs-write.md#descriptor-duplication-and-redirection>).

[Violating fixture](<../../test/caps/rules/violating/fs_read.ml>) and
[clean fixture](<../../test/caps/rules/clean/fs_read.ml>) form the rule/fixture/page triangle, checked by --self-check.

Compiled negative fixtures belong to a nested Dune project: the default scan excludes that separate workspace structurally. Explicit sources and annotations are still inspected. Repository tests compile and verify their findings; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).
