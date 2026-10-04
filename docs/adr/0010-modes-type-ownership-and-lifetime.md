# OxCaml modes type ownership and lifetime; Ox is the one trusted cast

Every bug found in ox since the master switch was a cancellation, wake-up, framing or keepalive bug (`docs/issues/stress/01-stress.md`), and two of them were ownership bugs: two fibers sharing one TLS ciphertext buffer (row 57), and resources used after the scope that owned them. OCaml's types do not see ownership or lifetime; OxCaml's modes do. This ADR decides that Ox's public API states ownership and lifetime in modes, so that a class of wrong agent-written code does not compile, and records what modes cannot do so nobody re-opens it.

## Decision

- **Ox owns the boundary to Eio.** Eio's interfaces carry no mode annotations (checked 2026-10-03 on the pinned Eio and upstream), so every Eio closure parameter is legacy: `global many nonportable`. Ox's wrappers take the precise modes (`@ once` for fork bodies and releases, `@ local once` for in-place callbacks, `@ unique` for owned handles, `@ local` for handles that die at return) and convert once, inside Ox, with `Obj.magic_many` behind a one-shot guard (`Ox.Once.guard`), which makes the cast unobservable. `lib/ox/once.ml` is the only file allowed to call an `Obj.magic_*` function; the gate enforces it.
- **Raw Eio concurrency is off-limits to consumers** (`raw-concurrency-gate`), the same way raw `Unix.fork` is: without that, every mode guarantee is opt-in.
- **Shapes follow Jane Street's `await` and `capsule`** (`Await.t @ local` as the capability to suspend, `Await.Scope.with_`'s local scope and `local once unyielding` body, `Capsule`'s branded data and access tokens, `Await.Cancellation`/`Or_canceled`), so that the day those packages are installable on our compiler the swap is mechanical. They are not installable today: every `ppxlib+ox` in `oxcaml/opam-repository` requires `ocaml < 5.3.0` (locked rev `d65f0810` and `main` `f1bd228d`, 2026-09-21), and `capsule`, `capsule0`, `await`, `portable`, `unique`, `handled_effect` all need `ppx_template` on top of it. `basement` installs, and contains no capsule.
- **Binding operators are the one ergonomic wall.** OxCaml elaborates `let*` with a `global unyielding` continuation, so a `local` scope handle or a `yielding` suspension token cannot cross a `let*` ("used in a letop"), and a `let*` declared with a local continuation is rejected. An ordinary application `bind r (fun x -> ...) [@nontail]` with `f : _ @ local once yielding` typechecks and keeps every refusal. Ox therefore gets a `let%bind`-style rewriter (`ppx-let`), as ppx_let is Jane Street's answer.

## Verified on 5.4.0+ox (2026-10-03, standalone compiles against the pinned Eio)

Refused, with the compiler's reason: a unique value moved into two forks ("already been used as unique"); a unique value captured by raw `Eio.Fiber.fork` ("expected to be many"); use after a consuming close; a `local` scope stored, returned, or captured by a fork; a `yielding` token used inside an `unyielding` critical section ("io is yielding but is expected to be unyielding") — through a plain `bind` too; a branded datum read without the lock, with another lock's access, or the access leaked ("would escape its scope"); a write to a mutable field of a `t @ read`. Accepted: the same programs written correctly, including through `bind` with `[@nontail]`.

## Not expressible, and therefore not attempted with modes

- *Must* await, close, or handle: OxCaml has affine `once`, not linear; a unique value may be dropped. Gate rules cover discarded `result`s.
- Swallowed `Eio.Cancel.Cancelled`, a finalizer that suspends, a Stdlib mutex held across a yield: not typed. Gate rules.
- Timing (keepalive under flood, lost wake-ups): the seeded stress layer.
- `unyielding` alone does not stop suspension: `Effect.perform` and `Eio.Fiber.yield` are not mode-checked. Only the token pattern (`suspend-token`) works.
- `stateless` closures: unusable while the stdlib is unannotated (`(+)` is stateful on 5.4.0+ox).

## Considered options

- **Patch Eio's signatures.** Rejected: Eio is used as released (the oxcaml/eio snapshot is being removed); the annotations live in Ox's wrappers instead, and an upstream PR stays possible.
- **Wait for `capsule`/`await`.** Rejected as the plan, kept as the destination: the blocker is outside our control and the shapes can be copied now.

## Checked against the published material (2026-10-04)

Five research passes (kept in [docs/issues/usage-rules/research/](<../issues/usage-rules/research/>)) looked for prior art. What they establish:

- **The four patterns this ADR uses are the published ones.** A `local` uninhabited token as proof of context is Jane Street's own device (Bonsai's phase witness, `handled_effect`, and `Effect.Handler` on OxCaml `main`: "A value of type [Effect.Handler.t] at mode [local] is proof that the current function is running within an effect handler"). `@ unique` for consume-once resources is their worked file example ("Since `close` requires a unique parameter, we can be sure that files are never used after being closed"), with `borrow_` for reading without forfeiting. `@ unyielding` on a callback parameter is the published spelling of "this callback must not suspend" (`Await.Mutex.with_access`, `Effect.Deep.Safe.match_with`). And **capability absence** is the strongest spelling of all, in `parallel/kernel`: "Subtasks must not [Await] or [Yield]; [Parallel.t] does not provide the capability."
- **The `let*` limitation is known upstream and is being worked on.** `parsing/parser.mly` on `main` still carries the comment "CR zqian: support mode annotation on letop"; `typing/typecore.ml` pins the body with a const closure lock; the compiler's own `testsuite/tests/typing-modes/letop.ml` records "bindings are required to be legacy" and "Body required to be legacy"; and PR #6276 parses modes on binding operators while fatal-erroring for now, saying "Actually checking these modes against user annotations will come next." There is no issue about the *mode of the continuation*. The `bind ... [@nontail]` route this ADR relies on is structurally sound for the same reason `ppx_let` works: it is an ordinary application, so the mode comes from `bind`'s signature and not from the letop lock. Row 69 therefore stands, and row 70 is not blocked.
- **Two limits, verified against the pinned compiler rather than inferred.** `Effect.Handler` and `Effect.Safe` do not exist in 5.4.0+ox (`effect.mli` contains no `Handler`), so a proof-of-context token must be ours. And every Eio suspension point ox calls is unmoded — `Time.sleep`, `Condition.await`, `Fiber.yield`, `Process.await` — so **the `yielding` axis has nothing to bite on until suspension is routed through Ox's own API and the gate refuses the raw call.** That is why row 71 depends on row 66, and why the token may end up as a capability in `ox_caps` rather than a type of its own.
- **Alerts are a compiler-level gate we own and do not use.** `[@@alert mint]` already exists on the powerbox constructor and nothing makes it fatal; `-alert @mint` in dune's `env` would add a third independent surface to the minting rule (row 66 story 11). Alerts cannot be attached to third-party values, so they complement the gate rather than replace it.

Nothing here reverses a decision above. The one correction it forces is to the hope that `unyielding` is self-enforcing: it is not, and the enforcing mechanism is Ox owning the suspension surface.
