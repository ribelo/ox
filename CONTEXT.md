# Ox

Ox is the kernel that Rafal's OCaml services are built from: one way to structure a process, typed failures, scoped resources on Eio, and the protocol code those services share. It exists so that every application is written the same way and every failure has a name.

## Language

### Shape of an application

**Kernel**:
Ox itself: the set of packages an application is built from. A kernel supplies structure and protocols, never application logic.
_Avoid_: framework, runtime, platform

**Floor**:
Scala Ox's table of contents (https://ox.softwaremill.com), which ADR-0009 makes the checklist of this library's core: everything on it exists in direct style over Eio or is recorded with a reason in `docs/design/ox-floor.md`. Scala Ox is the floor; Cause and the handler discipline of ADR-0006 are what this library adds above it.
_Avoid_: baseline, feature parity

**Door**:
The one entry point that turns a Program into a process: it builds the Env, decodes Config, installs signal handling, runs the Program, renders its Cause on failure, and returns the exit code.
_Avoid_: main, runtime, run_main, bootstrap

**Program**:
The function the Door runs: from Env and Config to a result. A Program acquires Services in dependency order inside one Switch and then serves until stopped.
_Avoid_: effect, blueprint, app

**Service**:
A module of one fixed shape: a type, a config, the Deps it needs, a typed error, `create` against a Switch, and `status`. Every long-lived part of an application is a Service.
_Avoid_: component, layer, provider, subsystem

**Deps**:
The record of Services and Env values a Service needs, passed to `create`. Wiring is ordinary code; there is no registry.
_Avoid_: coeffect, requirement, context, injection

**Resource**:
Anything acquired against a Switch and released when that Switch ends: a process, a socket, a Service.
_Avoid_: managed value, activation

**Env**:
Eio's standard environment plus the observability handles the Door creates. Programs and Services receive the specific Env values they use, never the whole Env.
_Avoid_: capability, runtime, environment (unqualified)

**Config**:
The decoded, validated configuration a Program receives from the Door: a plain type with `[@@deriving yojson]` (ADR-0008) whose derived decoder and encoder plus an environment function of its own make up the `Ox_app.Config.t` bundle the Door is handed.

**Status**:
What a Service reports about itself when asked, read from its real state at that moment.
_Avoid_: health, phase, diagnostics

### Failure

**Cause**:
The reason a computation did not succeed: a typed failure, a defect (an exception), an interruption, a finalizer failure, or a composition of those.
_Avoid_: error (when the structure matters), exception

**Exit**:
How a scope ended: success with a value, or a Cause.

**Typed failure**:
The `Error` side of a `result`, named by a polymorphic variant. The failure a caller is expected to handle.
_Avoid_: exception, fault

**Defect**:
An exception that escaped. Never part of a function's contract; always a bug or a broken invariant.

**Interruption**:
Eio cancellation observed at a scope boundary, carrying the identity of what requested it.
_Avoid_: cancel (as a noun), abort

### Concurrent data and flow

**Flow**:
A lazy description of a stream, after Ox's `Flow`: it does nothing until it is run, carries a typed error, and forks fibers only in the stages that need them. Designed in `docs/design/flow.md`; not yet built.
_Avoid_: pipeline, observable, reactive stream

**Channel**:
A bounded queue between fibers that can be closed with `Done` or a typed error, the thing `Eio.Stream` lacks and `Select` needs.
_Avoid_: mailbox, queue

**Actor**:
One fiber that owns a state and folds a bounded mailbox of typed messages over it, one at a time: `ask` waits for the reply, `tell` does not, and a typed refusal leaves the state as it was. It lives exactly as long as its Switch. A Service that keeps shared mutable state is usually one Actor.
_Avoid_: agent (that is the message-free module below), process, GenServer

**Agent**:
An Actor without a message type: one fiber owns a state and runs the closures callers submit (`get`, `update`, `get_and_update`, `cast`) serialized. The small shared counter, cache or handle holder.
_Avoid_: actor (when no message protocol is involved), ref, atom

**Supervisor**:
An opt-in restart boundary under a Scope: it runs child incarnations in their own nested scopes and restarts them by an OTP-style strategy, restart type and restart intensity, or ends its owning Scope with a typed failure. It is not a process runtime and creates no links.
_Avoid_: process tree, watchdog, monitor

**Select**:
Waiting on several channels at once and acting on whichever clause is ready first, with default and timeout clauses; a closed channel is a typed outcome, not an exception.

**Rate limiter**:
A permit dispenser over an injected clock (fixed window, sliding window, token bucket, or a custom algorithm) that blocks or drops an operation until a permit is available. It replaces a sleep between requests.
_Avoid_: throttle (that is a Flow stage), semaphore

### Time and repetition

**Schedule**:
A pure description of when to run something again: delays, limits, jitter, and their combinations. Applied by `retry` and `repeat`; it never runs anything itself.
_Avoid_: policy, backoff (as the whole), timer

**Duration**:
A length of time at millisecond precision.

### Retired words

These named v1 concepts and must not be reused: effect (as a noun for Ox's type), blueprint, interpreter, runtime, SPI, capability, component, coeffect, capsule, settlement fence, dormant provider, desired state, activation, eta (the library's name before the rename of 2026-09-29; it named an effect type that no longer exists).
