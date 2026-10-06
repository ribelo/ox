# Interface documentation contract

Row 89: ^nlintd-von6 ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn ^nlintd-a7oq.

Document behaviour from the implementation, not from the handle's name. If a callback, upstream dependency or cancellation race has not been audited, leave the missing claim in the [per-val reason ledger](../issues/ox-lint-docs/triage.md). The linter checks **sentence shape and finite typed implementation evidence**. Definite contradictions fail; unavailable or opaque evidence is a named undecided, fatal under `--require-typed`. Concurrency tests are still needed for behaviour outside that evidence model. ^nlintd-truth ^nlintd-raises ^nlintd-cleanup

## Required sentences

Each selected `val` needs four period-terminated fields, in its attached `(** ... *)` documentation or an inherited default:

| Field | Accepted beginning |
| --- | --- |
| Suspension | `Suspension: never suspends ... .` or `Suspension: may suspend ... .` |
| Cancellation | `Cancellation: not a cancellation point ... .`, `propagates ... .`, `protected ... .`, `classified ... .` or `depends on ... .` |
| Finalizers | `Finalizers: ... .` (nonempty) |
| Locking | `Locking: ... .` (nonempty) |

State where suspension/cancellation occurs, who owns cleanup and when it runs, and whether a lock spans caller code. Domain-blocking Unix calls are not Eio suspension points. An arbitrary callback can suspend even when its wrapper performs no Eio operation. Say which callback governs the answer instead of claiming the wrapper makes it safe.

A selected operation also needs one of these cancellation-safety sentences:

- `Cancellation safety: safe to re-run ... .`
- `Cancellation safety: unsafe because data is lost ... .`
- `Cancellation safety: unsafe because progress is lost ... .`

Explain what is retained, lost or already committed; `cancellable` and `unsafe` alone do not classify retry safety. No safety sentence is required when both `Suspension: never suspends ... .` and `Cancellation: not a cancellation point ... .` are present, or when `Cancellation: protected throughout ... .` explicitly covers the whole operation. Protecting only a callback does not exempt its caller's earlier/later waits.

## Existing good contracts

These existing Ox sentences are semantic exemplars. The linter checks reachable waits, checks, explicit raises and recognised cleanup obligations, not the whole sentence or protocol law:

- [Channel.send](../../lib/ox/channel.mli): “[send t v] appends [v], suspending while the buffer is full.” Name that wait rather than simply saying “asynchronous”.
- [Scope.run](../../lib/ox/scope.mli): “Cancellation is classified as [Interrupt].” Name the classification when a boundary returns cancellation rather than propagating it.
- [Concurrent](../../lib/ox/concurrent.mli): “the cancellation if cancelled” distinguishes the cancelled-switch exception from `Invalid_argument` for a finished switch.
- [Resource](../../lib/ox/resource.mli): “releases run in reverse registration order after every fiber of the switch has finished, with cancellation protected”. This states ownership, ordering and protection.
- [Actor implementation](../../lib/ox/actor.ml): “so the flags below need no lock.” The preceding no-suspension argument is its evidence; a typed handle alone proves no locking law.

## Typed selection

The rules share one predicate over compiler-matched `.cmti` signatures. It examines each explicit `Tsig_value` type, including inputs, outputs and callback types. Recognised families are Eio/Ox switches and scoped forks; Eio wall/monotonic clocks; resources, flows and paths; streams/Ox channels; actors, agent handles and actor-change subscriptions; Eio mutexes/pools, blocking-pool handles and SQL pool runners; genuine `Ox_caps.Cap.Token` and door capabilities.

Resolved declarations and compiler type identities distinguish real dependencies from local lookalikes. The traversal follows transparent aliases, instantiated parameters and visible record/variant fields, with cycle guards. A pure type called `Switch.t` is not selected. A hidden, unrelated abstract `t` is not guessed to be an I/O handle. Opaque re-exports and implicit values inside an unexpanded signature include are outside this explicit-val inventory. Pure values with no recognised family are left alone; constructors storing a dependency are selected even when their own behaviour is pure.

## Module defaults

A module paragraph begins `Cancellation and finalizers:`:

```ocaml
(** Cancellation and finalizers:
    Suspension: never suspends for these accessors.
    Cancellation: not a cancellation point for these accessors.
    Finalizers: no switch hook is registered; ownership is unchanged.
    Locking: no lock is acquired.
    ^nlintd-4ja0 *)
```

Free signature paragraphs apply to the whole signature regardless of textual position. Leading paragraphs attached by the parser to its first declaration are also recognised. Defaults attached to module/module-type declarations apply to their signatures. Children inherit defaults; siblings do not inherit a child's changes. Per-val fields override corresponding defaults. Overriding suspension or cancellation discards inherited cancellation safety unless that val supplies it again. Put a blank line between an attached doc comment and the next declaration to avoid OCaml attaching it twice.

Labels and shape prefixes are case-insensitive; whitespace is normalised. Each label must occur once in a local/default paragraph. Duplicates, empty fields, vague prefixes and missing sentence-ending periods are invalid. Dots within `Eio.Switch.t` do not terminate a sentence. The header itself is not a `Finalizers:` field. Shape acceptance alone says nothing about truth; the implementation-evidence pass is separate.

## Implementation evidence

The paired implementation and sibling `.cmt` files supply a finite typed call graph. Physical-expression memoization and application states keyed by typed callee node, partial/invocation mode and labelled actual substitution prevent recursive AST re-expansion; pending prefix and closure nodes are published before recursive demands are followed, and constructing a partially applied case-function does not execute its cases. Regenerating alias substitutions with no finite key remain named undecided, never depth-capped; a reverse-dependency work queue propagates monotonically growing effect sets. Function bodies are analysed when invoked, not merely when a callback is created. Compiler-normalised paths identify Eio semantic leaves, primitive contracts, exceptions and cleanup operations; a local lookalike does not become a scheduling point or destructor by its name. Transparent generated Dune wrappers contain aliases, empty nested structures or constant bindings but no executable calls; their compiler paths resolve to the real compilation units. Direct exported Eio function aliases use the same leaf semantics as applications; retrieving a non-function value is not an invocation. Source-verified immediate callback arguments are followed into their typed bodies; unavailable external invocation is named, not assumed. The known non-suspending compiler primitives and source-verified Eio allocation leaves are explicit small tables, not blanket Stdlib/Eio exemptions. ^nlintd-truth

The verifier checks consistency with reachable behaviour and disclosure of reachable suspension points, not proof of readiness/capacity invariants. A never-suspending/non-cancellation-point sentence can name a readiness-dependent leaf and its invariant (for example `Eio.Stream.add` into a reserved free slot); an unconditional yield or an undisclosed wait still contradicts it. The verifier checks no-suspension/no-cancellation-check claims against reachable Eio leaves, explicit raises against exception prose and `@raise` tags, and recognised typed channel acquisitions against ordered same-resource cleanup witnesses; Eio path/network acquisitions with their mandatory switch use the upstream registration contract. Unguarded constructor handlers remove caught exceptions; constrained payloads and guards do not establish a general catch. Constant boolean branches and `assert true` are pruned. Cancellation protection masks cancellation delivery, not explicit exception raises; no-added-check claims still see shielded checks.

Callback reachability retains the callee's exception handlers, cancellation protection and wrapping before substituting the actual callback. Thus a local protector catching [Sys_error] removes a callback's [Sys_error] from its caller, but not an uncaught exception, a guarded catch, or another unprotected invocation of that same callback. Canonical finite exception transfers keep recursive forwarding from accumulating handler stacks. A closure passed to [Hashtbl.add] or [Hashtbl.replace] is stored, not invoked; its own summary is retained and an explicit later call still contributes its effects. A callback loaded through an unresolved data structure is a named returned-function uncertainty, not proof of purity. These are callback-position/ownership semantics, not exemptions from callee effects. ^nlintd-truth ^nlintd-raises

[Fiber.fork], [Fiber.fork_daemon] and [Fiber.fork_promise] separate caller startup from owned child execution: Eio synchronously checks the switch's domain/lifetime and can raise [Invalid_argument], but does not run the child's cancellation check in the caller. A child's raises fail its owner switch or settle its promise; they are not synchronous raises of the spawn call, even if scheduling starts the child immediately. Caller waits and joins remain caller effects: [Promise.await_exn] can check cancellation and re-deliver an unresolved stored exception, while [Domain_manager.run] waits for its domain and propagates callback failures. An enclosing switch boundary may join and re-deliver child failure; it is not a detached-fiber exemption. If the external boundary body or callback ownership is unavailable, its named callback invocation stays unresolved unless the relevant claim explicitly discloses that delegated limit. Ownership prose does not document a different synchronous startup exception. ^nlintd-truth ^nlintd-raises

Only a claim depending on unresolved evidence becomes undecided; shape-only missing documentation does not demand opaque implementation evidence. An opaque dependency, callback parameter, partial application or returned closure, or unsupported functor path is named undecided unless the relevant effect sentence explicitly states that limit. Unknown exception identities from a dynamic re-raise or stored promise exception affect exception assertions, not known suspension/cancellation semantics. Module-type declarations still require shape documentation, but have no executable binding whose behaviour could be verified. “Locking is delegated” does not qualify “never suspends”. A qualification must name the dependency or caller callback governing the answer. Unavailable bodies, stale fingerprints and generated wrappers containing executable calls cannot be excused by prose. Cleanup through unsupported helpers remains undecided; qualifying a helper does not invent a resource-release witness.

This is not arbitrary path feasibility, termination, lock-order, idempotence or protocol-state proof. Whole-package effect propagation can cost more than linear time in highly connected graphs because each discovered effect travels along reachable edges; it never unfolds recursively to a nesting-depth cap. Runtime must be measured beside the recorded 2.4 s `lib/` baseline, not inferred from small fixtures.

## Running the rules

Build with the same compiler as the tool. `dune build @install` covers installed library interfaces; `dune build @check` also retains typed evidence for private executables and tests. Then run `ox-lint --require-typed --rules ox-val-behaviour --rules ox-cancel-safety path/to/api.mli`. Build membership comes first from `dune describe workspace`; sources absent there are checked against `dune describe rules --recursive @@<owner>/check` for compilation owners derived only from the selected sources and Dune metadata, including test stanzas omitted by Dune 3.22’s workspace description. The double-at alias excludes descendant aliases; `--recursive` follows compiler dependencies. Literal data-only ancestry prevents bogus fixture owners but never removes source candidates; unsupported declarations do not prove exclusion. Direct compiler producer inputs also authenticate generated empty interfaces. Only absence from both successful inventories is “not built”; the diagnostic names both sources. An unavailable inventory never proves exclusion. For a default whole-repository gate, all inventory queries finish first, then the tool rebuilds `@check` once per workspace and reads annotations without re-querying inventory. Dune’s rule-description queries can regenerate `(deps (universe))` targets without recompiling their annotations; rebuilding repairs that ordering, not digest checks. The summary discloses `rebuilt @check in 1 workspace`. `--root DIR` selects rule pages and self-check fixtures, not the scan scope. With no positional PATH, `--caps-gate` scans the current directory’s workspace and performs that `@check` rebuild. To inspect another workspace without rebuilding it, supply its path explicitly, for example `ox-lint --caps-gate --require-typed /path/to/consumer/lib`; explicit scans inspect supplied evidence without rebuilding. Staleness surviving the rebuild remains undecided and names the producer. Dune 3.22 has no non-building rule-description form: alias-free and targeted rule queries were also observed to regenerate volatile targets. ^nlintcov-q6n2 Missing or stale build-target evidence is undecided, not a clean documentation result. `--self-check` verifies both rule pages and their clean/violating fixtures exist; it does not validate contract truth.
