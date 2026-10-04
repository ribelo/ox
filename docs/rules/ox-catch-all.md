# ox-catch-all

Story: ^nlintc-du4v; evidence: ^nlintc-kdcl.

A cancellation is control flow, not an ordinary failure to suppress. Preserve it:

```ocaml
try work () with
| Eio.Cancel.Cancelled _ as exn -> cleanup (); raise exn
| _ -> () (* Intentional suppression of ordinary exceptions. *)
```

The typed tier reports a cancellation-origin constructor aliased to the complete
exception when its handler contains **no propagation of that binding**. A bare
wildcard, `exn` or `_exn` handler must contain such a re-raise, or follow an
unguarded cancellation arm containing one. Both `try` and
`match ... | exception ...` are checked. A guarded cancellation arm cannot
justify a later wildcard. Specific non-cancellation exception arms are unaffected.

**Cleanup before re-raising is legitimate.** Release the resource, run an on_cancel
hook, emit an interrupt end event with its backtrace, or roll back a transaction,
then propagate. The recognizer follows expressions throughout the handler,
including sequences, lets, conditionals and inline cleanup callbacks; an
origin-resolved `raise`, `raise_notrace` or `Printexc.raise_with_backtrace` whose
first argument is the original binding counts, even on only one branch. It is
not an all-path reachability proof. Throwing a different exception does not count.

**Reifying is propagation too.** A handler is also clean if its result carries
the bound exception: a variant payload, tuple component, record field or
`Error exn`. Tail sequences/lets, conditionals, matches and try arms are inspected;
constructing `Error exn` and then discarding it does **not** count. The rule proves
only that the exception leaves the handler, not that a caller ever re-raises it.
A caller that drops a reified exception is an accepted false negative. Value
aliases and opaque construction helpers are not followed.

**Separate hazard deliberately not covered:** suspension after catching a
cancellation and before re-raising it. This rule rejects swallowed cancellation,
not delayed cancellation propagation. Detekt treats that suspension as a separate
case; folding it into this rule would reject legitimate cleanup-first handlers.

**Resolution and accepted false negatives.** The constructor is compared by
normalized extension origin, never by spelling or UID alone. Module aliases and
opens resolve through the typed environment. Same-unit `exception Stopped =
Eio.Cancel.Cancelled` is followed using `Text_rebind` origin metadata; the spike
showed unequal UIDs even for that rebinding. **Cross-unit exception rebinding is
unproven** and is not claimed supported. Unbound cancellation arms, other binding
names (such as `error`), complex disjunctive/guarded catch-all patterns and
interprocedural propagation are outside the decidable set. A re-raise in an
unreachable branch or deferred closure can cause a false negative. The rule does
not classify arbitrary matches over exception values (e.g. Scope's Cause
boundary). No allow-list entries.

## Evidence

The first full tree scan examined 14 production sites where row 66 had counted
five. With legitimate cleanup-first propagation and exception reification
recognized, **10 actually swallowed cancellation**: the original five and five
additional sites. Four already propagated correctly and were left unchanged.
The CLI engine had a separate broad printer-fallback catch; it now queries
`Location.error_of_exn` rather than suppressing a printer exception.

[Violating fixture](<../../test/lint/violating/catch_all.ml>) and
[clean fixture](<../../test/lint/clean/catch_all.ml>) are compiled and checked by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.

Compiled negative fixtures use a file-level `ox_lint.fixture` marker naming their rule: only the default scan skips them; explicit scans retain every finding and reject a dead marker when its rule is selected. Repository tests verify these findings with typed evidence; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).
