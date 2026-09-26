# Effect handlers are for domain-owned stepping, and nothing else

OCaml 5 effect handlers let a computation suspend and hand its continuation to a handler that decides when, whether, in what order, and how often it resumes. That is the one thing no other direct-style mechanism does, and it is the only reason to use them. The test for a candidate effect is: **would any handler ever hold the continuation** — resume later, out of order, more than once, or never? If every handler would resume at once with a computed value, the operation is a function parameter, not an effect; ambient values are parameters or Eio fiber-local bindings, aborts are `result`, concurrency and I/O are Eio's handlers already. This follows Jane Street's own framing in "Fun with Algebraic Effects — from Toy Examples to Hardcaml Simulations": the computation is plain sequential code, the handler is a scheduler, and the value appears when the *domain* owns the stepping (a simulated clock, a protocol step, an agent's decision step, an iteration) rather than the operating system.

Two constraints from the 2026-09-26 spike (ADR-0002): the computation holding a handler token must not cross `Switch.run` or a fiber fork — it lives in one fiber, while its handlers may use all of Eio — and a perform costs about 50× an `Error`/`match`, so effects are never on a hot path that a parameter could serve. Every effect eta-next or a consumer defines uses the local-token pattern (a handler value at mode `local`, required by `perform`) so that "unhandled" is a compile error; `Handled_effect` itself when it becomes installable on 5.4.0+ox, the 25-line equivalent until then.

## Consequences

- The kernel defines no effects today: config, errors, resources, retry and concurrency all fail the test.
- Recognised candidates: pull streams and generators (yield is domain-owned stepping); Leash's drive loop, written as a computation performing `Observe`/`Decide`/`Act` with production, scripted-test and human-inspector handlers.
- A new effect needs the three answers written in its spec: what holds the continuation, who owns the stepping, and why the computation stays in one fiber.
