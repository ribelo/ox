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
