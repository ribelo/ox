# Eta

Eta is the kernel that Rafal's OCaml services are built from: one way to structure a process, typed failures, scoped resources on Eio, and the protocol code those services share. It exists so that every application is written the same way and every failure has a name.

## Language

### Shape of an application

**Kernel**:
Eta itself: the set of packages an application is built from. A kernel supplies structure and protocols, never application logic.
_Avoid_: framework, runtime, platform

**Door**:
The one entry point that turns a Program into a process: it builds the Env, decodes Config, installs signal handling, runs the Program, renders its Cause on failure, and returns the exit code.
_Avoid_: main, runtime, run_main, bootstrap

**Program**:
The function the Door runs: from Env and Config to a result. A Program acquires Services in dependency order inside one Switch and then serves until stopped.
_Avoid_: effect, blueprint, app

**Service**:
A module of one fixed shape: a type, a config, the Deps it needs, a typed error, `create` against a Switch, and `status`. Every long-lived part of an application is a Service.
_Avoid_: component, layer, provider, subsystem, actor

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
The decoded, validated configuration a Program receives from the Door: a plain type with `[@@deriving yojson]` (ADR-0008) whose derived decoder and encoder plus an environment function of its own make up the `Eta_app.Config.t` bundle the Door is handed.

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

### Time and repetition

**Schedule**:
A pure description of when to run something again: delays, limits, jitter, and their combinations. Applied by `retry` and `repeat`; it never runs anything itself.
_Avoid_: policy, backoff (as the whole), timer

**Duration**:
A length of time at millisecond precision.

### Retired words

These named v1 concepts and must not be reused: effect (as a noun for Eta's type), blueprint, interpreter, runtime, SPI, capability, component, coeffect, capsule, settlement fence, dormant provider, desired state, activation.
