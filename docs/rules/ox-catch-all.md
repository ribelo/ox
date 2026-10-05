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
including sequences, lets and conditionals, but not deferred function bodies; an
origin-resolved `raise`, `raise_notrace` or `Printexc.raise_with_backtrace` whose
first argument is the original binding counts, even on only one branch. It is
not an all-path reachability proof. Throwing a different exception does not count.

**Delegating propagation is legitimate.** A direct call passing the original bound
exception is followed into a resolvable local or same-package helper through fresh,
checked typed artifacts. Parameter position, local aliases and recursion are tracked;
the helper must visibly re-raise that original value. A logging helper, opaque external
function or unavailable/stale helper implementation remains a finding: propagation
is unproven, not licensed by the helper's name. Merely creating a closure that later
raises the exception does not propagate it. ^nlintc-du4v ^nlintc-kdcl

**Reifying is propagation too.** A handler is also clean if its result carries
the bound exception: a variant payload, tuple component, record field or
`Error exn`. Tail sequences/lets, conditionals, matches and try arms are inspected;
constructing `Error exn` and then discarding it does **not** count. The rule proves
only that the exception leaves the handler, not that a caller ever re-raises it.
A caller that drops a reified exception is an accepted false negative. Value
aliases and opaque construction helpers are not followed.

**A store needs visible use.** Storing the original exception (possibly in a tuple,
variant or record payload) in a ref or mutable record field counts only when the
visible continuation returns the stored contents, asserts about them, or scrutinizes
them in a non-wildcard match. An unread store, ignored dereference, deferred reader
or intervening overwrite stays a finding. The target must be origin-resolved and
identifiable; this is not arbitrary heap or whole-program use tracking. Rendering an
exception to text does not preserve the original exception. ^nlintc-du4v ^nlintc-kdcl

**Terminal entry conversion is narrowly proven.** A handler may convert cancellation
only when it directly contributes the status argument of an origin-resolved
`Stdlib.exit` or `Ox_caps.Cap_stdlib.exit` in the named executable entry, or is the
tail result of the final inline Program callback of `Ox_app.run_and_exit` or
`Ox_app.run_and_exit_with_args`. Only tail sequences, let bodies, conditional results
and match/try results are traversed. Let right-hand sides, discarded sequence prefixes,
unknown callbacks, named/deferred programs, refs/record-result routes, optional Door
callbacks, utility modules and library initializers receive no terminal privilege.
Returning a rendered error or status to a continuing caller is still a finding.
^nlintc-du4v ^nlintc-kdcl

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
opaque interprocedural propagation are outside the decidable set. A re-raise in an
unreachable branch can still cause a false negative; deferred closures do not count.
The rule does
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
[Executable-entry fixtures](<../../test/lint/entry/exit_entry.ml>) and
[Door fixtures](<../../test/lint/entry/app_entry.ml>) pin both terminal acceptance and
continuing/deferred rejection, alongside actual utility and library modules.

Compiled negative fixtures belong to separate nested Dune projects, which the default gate does not descend into. The workspace still builds their typed evidence; explicit scans retain every finding, and exact-site regression tests fail if a fixture stops violating. Installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>) (^ncapslint-2606).
