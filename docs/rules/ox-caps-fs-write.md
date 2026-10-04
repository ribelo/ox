# ox-caps-fs-write

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

A resolved raw fs-write reference is legal exactly when an enclosing function argument supplies genuine Cap.fs_write authority. Argument authority may be captured by a nested callback or carried in a record, tuple, option, variant or payload. Wrappers obey the same definition; wrapper paths are not exempted.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

The source tier reports naked or argumentless references. Non-wildcard/non-unit parameters may carry authority, so such references defer to typed evidence; source-only success is not proof of genuine token identity. The typed tier follows normalized paths, token identities and argument provenance, not arbitrary opaque higher-order forwarding, dynamic loading or foreign-code behaviour. Missing/stale typed evidence is undecided; --require-typed fails it. Unix.dup and dup2 duplicate or redirect already-held descriptor authority; they do not mint filesystem authority. Metadata reads (Sys.file_exists, Unix.stat, Unix.realpath) are not raw write targets.

[Violating fixture](<../../test/caps/rules/violating/fs_write.ml>) and
[clean fixture](<../../test/caps/rules/clean/fs_write.ml>) form the rule/fixture/page triangle, checked by --self-check.

Compiled negative fixtures use a file-level `ox_lint.fixture` marker naming their rule: only the default scan skips them; explicit scans retain every finding and reject a dead marker when its rule is selected. Repository tests verify these findings with typed evidence; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).
