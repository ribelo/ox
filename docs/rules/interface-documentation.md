# Interface documentation contract

Row 89: ^nlintd-von6 ^nlintd-z5p5 ^nlintd-vneh ^nlintd-4ja0 ^nlintd-6abn ^nlintd-a7oq.

Document behaviour from the implementation, not from the handle's name. If a callback, upstream dependency or cancellation race has not been audited, leave the missing claim in the [per-val reason ledger](../issues/ox-lint-docs/triage.md). The linter checks **presence and sentence shape, never truth**. Concurrency tests and row 85 establish behaviour; a clean lint result is not that evidence.

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

These existing Ox sentences are semantic exemplars, not phrases the linter proves:

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

Labels and shape prefixes are case-insensitive; whitespace is normalised. Each label must occur once in a local/default paragraph. Duplicates, empty fields, vague prefixes and missing sentence-ending periods are invalid. Dots within `Eio.Switch.t` do not terminate a sentence. The header itself is not a `Finalizers:` field. Shape acceptance says nothing about whether the sentences are true.

## Running the rules

Build with the same compiler as the tool. `dune build @install` covers installed library interfaces; `dune build @check` also retains typed evidence for private executables. Then run `ox-lint --require-typed --rules ox-val-behaviour --rules ox-cancel-safety path/to/api.mli`. Missing or stale build-target evidence is undecided, not a clean documentation result. `--self-check` verifies both rule pages and their clean/violating fixtures exist; it does not validate contract truth.
