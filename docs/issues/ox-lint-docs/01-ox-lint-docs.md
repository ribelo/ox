---
status: ready
package: ox_lint (rules), every `lib/**/*.mli`
consumer: Ox (row 86 stories 6 and 9; the convention Eio practises and never wrote down)
---

# The interface-documentation contract, decided by `ox-lint`

## Problem Statement

Eio's `.mli` files state cancellation, finalizer and locking behaviour per function consistently, and the convention is written nowhere — not in its `HACKING.md` — so an agent cannot check itself against it (row 86, ^nguide-2hvs). Ox inherits the habit without the contract. Row 87's spike established that the material is reachable: **1,301 of 1,301** `val` declarations expose their name, span, type and attached documentation, and all **488** attached-doc sets match the source. It also established the size of the gap: **813** `val`s carry no attached doc at all.

## Solution

Write the contract, then check it: every `val` in `lib/**/*.mli` that can suspend, cancel, acquire or release says so, in a stated shape, and `ox-lint` decides it from the `.cmti`.

## User Stories

1. As a kernel maintainer, I want the contract written as one page — the sentence shapes for suspension, cancellation, finalizers and locking, with ox's own best existing examples quoted (`lib/ox/scope.mli`, `lib/ox/resource.mli`) — so that "documented" has a form and not a feeling. ^nlintd-von6
2. As a kernel maintainer, I want `ox-val-behaviour` to require that sentence on every `val` whose type involves a switch, a clock, a flow, a channel, an actor, a mutex or `Ox.Io` once row 71 lands, and to leave pure values alone, so that the 813 undocumented `val`s are triaged by type rather than all at once. ^nlintd-z5p5
3. As a service author, I want `ox-cancel-safety` to require, on every operation that can be cancelled midway, tokio's three-valued statement — safe to re-run, unsafe because data is lost, unsafe because progress is lost — since a caller retrying after a cancelled `receive` needs to know which. ^nlintd-vneh
4. As a maintainer, I want module-level defaults to count: a `(** Cancellation and finalizers: ... *)` paragraph on the module satisfies the rule for the `val`s it covers, so that the contract does not force 1,301 repetitions. ^nlintd-4ja0
5. As a maintainer, I want the rule to distinguish sentence shape from implementation evidence, reporting a false claim or a named undecided claim rather than treating a well-shaped sentence as proof. The historical shape-only checker is superseded by stories 8–10. ^nlintd-6abn
6. As a maintainer, I want the triage done in this row — every `val` the rule selects either documented or recorded in a list with a reason — and the count reported, so that the row ends with a number rather than a backlog. ^nlintd-a7oq
7. As a maintainer, I want the contract page and the rule cited from `docs/caps.md`'s sibling pages and from `AGENTS.md`'s "How code is written", so that an agent writing a new `.mli` meets it before the check does. ^nlintd-7r1a

8. As a kernel maintainer, I want no-suspension and no-cancellation-check claims compared with typed implementation reachability across the package, with opaque calls and invoked callback parameters named unless the sentence explicitly qualifies them, so that wrappers cannot claim what caller code does. ^nlintd-truth
9. As a kernel maintainer, I want documented exceptions matched against reachable explicit raises and known Eio cancellation checks, and unmentioned reachable raises reported, so that a sentence cannot invent Invalid_argument for cancellation. ^nlintd-raises
10. As a kernel maintainer, I want resource-cleanup claims compared with cancellation-path finalization, mutation fixtures that distinguish a real finalizer from success-only cleanup, and measured limits and whole-library runtime, so that safety-looking code is not enforcement. ^nlintd-cleanup

## Reachability bounds

Story 8 (^nlintd-truth) includes recursive local operators, curried functions and partially applied callbacks. Construction visits the typed callee node together with its labelled actual substitution and invocation/partial mode, publishes pending graph nodes before following recursive demands, and keeps distinct callback substitutions distinct. The final argument of a compiler case-function is separate from its explicit parameter list: forming the callback must not execute its cases. A regenerating substitution with no finite state remains named undecided; no depth cap, recursion-limit exemption or silent pass is permitted. The regression evidence includes a recursive mapper partially applied to a fixed environment (the shape reported by nema), quiet and suspending substitutions of that mapper, and mutually recursive function prefixes that retain a reachable yield. Whole-workspace gate wall-clock time is measured before and after the change.

Story 8/9 (^nlintd-truth ^nlintd-raises) also preserve callee handler/protection/wrapping semantics when substituting demanded callbacks, including recursive forwarding. A stored closure is not a demanded callback; a later proven invocation still propagates it, while an unresolved returned closure or external callback position remains named undecided unless its assertion explicitly bounds that delegated evidence. Fork caller startup (the synchronous switch domain/lifetime check) is separate from owned child effects; waits and joins retain caller suspension, cancellation and re-delivered failures. Paired regressions distinguish caught/uncaught and guarded callbacks, stored/invoked closures, and fork startup/parent waits.

## Out of Scope

Rewriting implementation behaviour or choosing intended retry semantics. Unsupported evidence must remain explicitly undecided; path feasibility beyond literal conditions and arbitrary user cleanup correctness are not proofs supplied by this checker.
