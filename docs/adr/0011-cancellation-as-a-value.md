# Cancellation as a value

Status: accepted 2026-10-04 (the coordinator reviewed the spike; reopened only by the evidence named in the last paragraph)

## Decision

**Reject cancellation-value tokens for now, including a named-operations-only rollout.** The requested shape compiles and composes with Ox, but the working implementation owns interruption state and wake-up registrations independently of Eio. That is a second cancellation model in [ADR-0001](<0001-direct-style-on-eio.md>)'s sense, despite having no second scheduler or interpreter. Keep typed timeout boundaries and Eio teardown; [ADR-0010](<0010-modes-type-ownership-and-lifetime.md>)'s resemblance to await does not establish equivalent cancellation semantics.

Answers [stories 1–4](<../issues/cancellation-value/01-cancellation-value.md>): ^ncancel-58b3, ^ncancel-yqo2, ^ncancel-cmec, ^ncancel-li9g. No library or consumer changes.

## Considered options

- **Adopt everywhere.** Rejected: token cancellation leaves unrelated Eio work running. Replacing root `request_stop` or race-loser teardown would require every blocking path to cooperate, or retain Eio cancellation beside it. Bare `Canceled` also loses requested-stop provenance.
- **Adopt for named operations only.** Works, but rejected as a kernel policy: the source owns a canceled bit, waiter registrations and lifetime; forks need per-fiber reborrowing. Linking tokens and supporting more operations extend this separate policy. Only named operations avoid wide-handler swallowing; implicit termination remains swallowable.
- **Typed view of one Eio context.** A private-reason adapter returned `Canceled`, but subsequent `Fiber.check` still raised until the context boundary exited. Canceling that child first also masked later parent cancellation in the naive adapter; the parent needs checking after boundary exit. This can be a boundary view, not an independently recoverable token. These controls are not an impossibility proof.
- **Translate owned boundary outcomes only.** Chosen, and specified as row 84 ([typed-boundaries](<../issues/typed-boundaries/01-typed-boundaries.md>)): the rule is that a boundary Ox itself owns reports its outcome as a value, while a foreign interruption stays Eio's exception, and the operations that still lack the typed form get it there. [Timeout.timeout](<../../lib/ox/timeout.mli>) already cancels and joins through Eio, returns typed `Timeout`, and propagates caller cancellation. Preserve implicit Eio teardown.

## Consequences

**No current Interrupt becomes a typed failure under this decision.** In a future token design, explicitly requested cancellation of a token-aware operation would become ``Cause.Fail `Canceled`` when propagated; deadline boundaries should retain ``Fail `Timeout``. Neither `Interrupt None` nor an arbitrary `Interrupt (Some id)` identifies voluntary cancellation by itself. Do not blanket-convert them.

Default Door outcomes, from the [mapper](<../../lib/app/ox_app.ml#L36-L47>) and [owned-command wiring](<../../lib/app/ox_app.ml#L94-L115>):

| Origin | Boundary outcome | Default exit |
| --- | --- | --- |
| Timeout.timeout deadline | ``Fail `Timeout``; canceled body joined | 1 through consumer exit_code |
| Door-recorded request_stop, including SIGINT/SIGTERM | Bare Interrupt (Some recorded id) | Service/run_owned: 0; run_owned_code: 130 (interrupt_exit) |
| Foreign cancellation or unrecorded stop ID | Interrupt None / Some unrecorded id | 2 |
| Sibling typed failure / defect | Original Fail e / Die; canceled siblings suppressed | 1 through exit_code / 2 |
| Race loser / normally stopped daemon | Internal Eio interruption, normally suppressed | No separate exit; winning success: 0 |
| Release failure / other non-bare Cause tree | Finalizer / Suppressed / mixed causes | 2 |
| Hypothetical propagated named-operation Canceled | ``Fail `Canceled`` | 1 through exit_code; handled success: 0 |

Replacing `request_stop` with bare `Canceled` would therefore change 0/130 to typed-error exit 1, and could leave non-cooperating fibers running. Preserving stop identity/provenance would need another decision. A canceled branch is an ordinary failure to first-success `race`; another branch may win. All-failed race returns a Cause *as its typed error payload*: propagating it through Scope.run produces outer Fail (exit 1), not a top-level Concurrent tree (exit 2).

### Verified evidence

On 2026-10-04, compiled standalone with **OxCaml 5.4.0+ox**, installed **Eio 1.6**, and real **Eio_main, Linux backend**. [Scope](<../issues/cancellation-value/spike/scope.ml>), [Concurrent](<../issues/cancellation-value/spike/concurrent.ml>) and [Timeout](<../issues/cancellation-value/spike/timeout.ml>) were unmodified copies. Scratch [Channel](<../issues/cancellation-value/spike/channel.ml>) gained condition registrations and token checks. Compiled public shapes ([Cancellation](<../issues/cancellation-value/spike/cancellation.mli>), [Channel](<../issues/cancellation-value/spike/channel.mli>), qualified here):

```ocaml
val with_ : (t @ local -> 'a) @ local once -> 'a
val receive : cancel:Cancellation.t @ local -> ('a, 'e) Channel.t ->
  ('a, [> `Canceled | `Done | `Error of 'e ]) result
```

- **18/18 runtime checks passed:** pre-canceled/blocked receive, payload/closed/error channels, no item consumption on cancellation, multiple waiters, supervised_error/par joining sibling cleanup, race success/all-failure, parent and same-turn parent/token cancellation, sibling defect, race loser, existing and token deadlines, unaffected ambient work, stale-source refusal, and swallowed-termination control. Expected token cancellation returned a value without raising; implicit cancellation still raised. Fiber.check before token inspection gave termination priority.
- **2/2 Eio-view controls passed**, exposing the boundary limitations above. A stack-local-capturing callback compiled and ran. **4/4 negative compiles refused** token escape, capture by Concurrent.par, direct local-once callback forwarding to Eio.Cancel.sub, and callback reuse. Composition used a global source and fresh local borrow per fiber; no casts.
- **12/12 checks of the verbatim [extracted Door mapper/request_stop](<../issues/cancellation-value/spike/door_mapping.ml>) passed**, using actual Scope.run exits: success 0; Canceled 1/custom 7; Timeout 1; recorded stop 0/130; missing provenance/foreign stop/defect/cleanup defect 2; race success 0; propagated all-failed race 1. Not a full Door CLI or real-signal test.

Reproduce via the scratch [runner](<../issues/cancellation-value/spike/run.sh>) from the repository root:

```sh
nix develop -c sh docs/issues/cancellation-value/spike/run.sh
```

Read await's oxcaml interfaces at revision `459ceb0f33ad10b90e11e8d37674e12041429107`: [cancellation](https://github.com/janestreet/await/blob/459ceb0f33ad10b90e11e8d37674e12041429107/kernel/cancellation.mli), [or_canceled](https://github.com/janestreet/await/blob/459ceb0f33ad10b90e11e8d37674e12041429107/kernel/or_canceled.mli), [terminator](https://github.com/janestreet/await/blob/459ceb0f33ad10b90e11e8d37674e12041429107/kernel/terminator.mli), [await](https://github.com/janestreet/await/blob/459ceb0f33ad10b90e11e8d37674e12041429107/kernel/await.mli), [scope](https://github.com/janestreet/await/blob/459ceb0f33ad10b90e11e8d37674e12041429107/sync/scope.mli). Its operations may raise on *termination*, not expected cancellation. Await itself was not installed/compiled. Rejection and root-stop migration consequences are **design inferences**; linked tokens, cross-domain use, allocation/performance and exhaustive scheduling were not verified. Reopen with an Eio-only recoverable-token prototype, or an explicit decision to amend ADR-0001—not modes alone.