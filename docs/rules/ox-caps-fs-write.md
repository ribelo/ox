# ox-caps-fs-write

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

A resolved raw fs-write reference is legal exactly when an enclosing function argument supplies genuine Cap.fs_write authority. Argument authority may be captured by a nested callback or carried in a record, tuple, option, variant or payload. Wrappers obey the same definition; wrapper paths are not exempted.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

The source tier reports naked or argumentless references. Non-wildcard/non-unit parameters may carry authority, so such references defer to typed evidence; source-only success is not proof of genuine token identity. The typed tier follows normalized paths, token identities and argument provenance, not arbitrary opaque higher-order forwarding, dynamic loading or foreign-code behaviour. Missing/stale typed evidence is undecided; --require-typed fails it. `Unix.dup` and `dup2` are deliberately not filesystem-write targets; the descriptor-possession decision below distinguishes duplication from process-standard-stream redirection. Metadata reads (Sys.file_exists, Unix.stat, Unix.realpath) are not raw write targets.

[Violating fixture](<../../test/caps/rules/violating/fs_write.ml>) and
[clean fixture](<../../test/caps/rules/clean/fs_write.ml>) form the rule/fixture/page triangle, checked by --self-check.

Compiled negative fixtures belong to a nested Dune project: the default scan excludes that separate workspace structurally. Explicit sources and annotations are still inspected. Repository tests compile and verify their findings; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).

## Descriptor duplication and redirection

Decision: ^nlintcov-d9u5. `Unix.dup fd` returns another handle to the same open description; it opens no new path and grants no authority the holder lacked. `Unix.dup2 src dst` is not merely duplication: it closes and rebinds the chosen destination descriptor. When `dst` is 0, 1 or 2 this redirects the current process's standard input, output or error; doing it between fork and exec is how a child's streams are captured.

Both descriptors must already be in the caller's hands. In this capability model possession includes redirection; passing the destination as a function argument explicitly transfers that authority. Neither operation gains a new capability classification. Filesystem tokens would misclassify socket descriptors, and `exec` means replacing a program image, not redirecting the current process.

Acquiring `Unix.stdin`, `Unix.stdout` or `Unix.stderr` raw requires the corresponding [stdin](<ox-caps-stdin.md>), [stdout](<ox-caps-stdout.md>) or [stderr](<ox-caps-stderr.md>) capability. Those descriptor references, including `dup2` destinations, are stream-rule roots. `dup2` with two supplied descriptors needs no additional token. The gate does not track descriptor-number provenance through arbitrary value aliases or opaque descriptor factories, nor restrict all operations on a supplied descriptor: those are explicit limits, not a claim to prove all process-global redirections safe.
