# Why eta-next, and how code is written here

This document records why the first design of Eta was abandoned, what replaces it, and how OCaml 5's effect handlers fit into the replacement. It is written for the next person — human or agent — who opens this repository and wonders why a framework that once had sixty packages now has a handful, and why nothing in it looks like TypeScript Effect any more.

## 1. What v1 was

Eta v1 (tag `v1`, May–September 2026) ported the core ideas of TypeScript Effect and ZIO to OCaml. A program was a value of type `('a, 'err) Effect.t`: a description — a *blueprint* — of a computation with a typed failure channel. Blueprints were composed with binding operators and combinators (`race`, `timeout`, `retry`, `with_background`, `acquire_release`) and interpreted by a `Runtime`, which mapped every operation onto a backend through an SPI. The shipped backend was Eio; a js_of_ocaml backend existed. Around the core grew HTTP/1, HTTP/2, WebSocket, TLS, OpenTelemetry, SQLite, twelve AI provider clients, reactive signals, incremental state machines, a component runtime with desired-state reconciliation, and a documentation and ticket system of sixty-four thousand lines.

Four months in, the applications built on it were Pie, inn, nema, taumel, grip, p-doom — all by one person — and the first new consumer, Leash, was being planned.

## 2. Why it was abandoned

Not because the ideas were wrong. Three of them survive intact, and they are the reason Eta exists at all:

- a **typed failure channel** that composes with concurrency, which neither Eio's exceptions nor a bare `result` gives you;
- the **Cause tree** — typed failure, defect, interruption with identity, finalizer failure, and their compositions — so that "what happened to this scope" always has a precise answer;
- **virtual time** in tests, so a thirty-minute expiry is a microsecond assertion.

It was abandoned because of the *interpreter*, and because of what the interpreter did to the project.

**The interpreter fought Eio.** OCaml 5's direction is direct style: effect handlers exist precisely so concurrency needs no monad, and Eio is the community's expression of that. A blueprint interpreter re-expresses every runtime concept — fork, cancel, mask, sleep, resource, finalizer — in its own vocabulary and then maps it back onto Eio. That mapping was four thousand lines of core, and every hard bug lived in it: interruption identity lost through nested `par`; `with_background` reporting a successful body as a finalizer failure; a service dying of a defect and printing nothing at the process door; a child process SIGKILLed by Eio's switch teardown concurrently with Eta's SIGTERM finalizer. Two cancellation models, kept in agreement by hand, resource by resource, forever. Meanwhile the one thing the interpreter uniquely enables — running the same blueprint on another backend — had zero users.

**Writing it became the activity.** Sixty packages, 124k lines of library, 218k of tests, 247 tickets, a tier system, a private vocabulary. A component runtime was designed, tested and adopted by Pie, then deleted by Pie because it had become a shadow of the real data path. A Linux input-device package lived in the framework with one consumer. JSON helpers were copied five times. The README described modules in packages they had left. None of this was carelessness; it was a process that could produce a package faster than a consumer could prove the need for one. The size of the thing was the symptom, not the cause.

**And the benefits did not need the interpreter.** That is the finding that made the decision. Typed errors are `result`. The Cause tree is a *classification of what came out of a scope*, computed by catching, not by interpreting. Virtual time is `Eio_mock.Clock`. Schedules are already pure data. Once those four facts are on the table, the interpreter is pure cost.

## 3. What eta-next is

A **kernel**, not a framework: the packages Rafal's services are built from, written in direct style on Eio, on OxCaml. It has one way to structure an application and it is small on purpose. Its rules, each recorded as an ADR:

1. Direct style on Eio; no blueprint, no interpreter, no second cancellation model (ADR-0001).
2. `('a, 'err) result` is the error channel; the Cause tree is computed at scope boundaries (ADR-0002).
3. Tabula rasa and pull-only: nothing exists here until a consumer's spec cites the story that needs it; pure codecs are copied from v1 when pulled, everything effectful is rewritten (ADR-0003).
4. One application model: Services, Deps, a Switch, a Door; no runtime dependency graph (ADR-0004).
5. OxCaml-first with a strict dependency policy: stdlib, Eio, Jane Street packages when installable on our compiler, unavoidable C bindings, and an ADR for anything else (ADR-0005).

Vocabulary is in `CONTEXT.md`. The words *effect*, *blueprint*, *runtime*, *interpreter*, *capability*, *component* and *coeffect* are retired.

## 4. How to write direct style here

### Errors

A function that can fail returns `('a, 'err) result` where `'err` is a polymorphic variant. Unions compose by inference; a caller that handles some cases narrows the type with `match`, and the rest flow up.

```ocaml
let fetch ~net ~clock url : (body, [> `Timeout | `Http of int | `Connect of Eio.Net.error ]) result = ...

let load ~net ~clock url =
  let open Result.Syntax in            (* let*, let+ over result *)
  let* body = fetch ~net ~clock url in
  let* doc  = Decode.document body in   (* [> `Decode of Decode.issue ] joins the union *)
  Ok doc
```

Exceptions are defects. They are never part of a contract, never caught to be turned into typed failures at random places, and always reported through the Cause at the nearest scope.

### Scopes, Cause and Exit

Eio already tells a scope everything: `Ok`/`Error` is a typed outcome, an exception is a defect, `Eio.Cancel.Cancelled ex` is an interruption whose `ex` names who cancelled, and a failing `Switch.on_release` is a finalizer failure. `Scope.run` catches at the boundary and builds the Cause:

```ocaml
type ('a, 'e) exit = Ok of 'a | Error of 'e cause
and 'e cause =
  | Fail of 'e                      (* typed failure *)
  | Die of exn * Printexc.raw_backtrace
  | Interrupt of Interrupt_id.t option
  | Finalizer of 'e cause           (* cleanup failed after success *)
  | Suppressed of { primary : 'e cause; finalizer : 'e cause }
  | Concurrent of 'e cause list

val Scope.run : (Eio.Switch.t -> ('a, 'e) result) -> ('a, 'e) exit
```

Interruption identity is kept the same way v1 kept it — a private exception carrying an id is what a combinator cancels with — but now it is only ever *observed*, never *propagated by an interpreter*.

### Two kinds of errors

Ox's doctrine, adopted whole (ADR-0009):

- **Unrecoverable errors** are exceptions, untyped on purpose so that nobody builds control flow on them. They mean a bug or a broken invariant; nothing in a signature mentions them, and a combinator that meets one raises exactly that exception, adds nothing and swallows nothing. `Scope.run` classifies them at the boundary as defects.
- **Recoverable errors** are values: `('a, 'e) result` with a polymorphic variant for `'e`. They are the failures a caller is expected to handle, and Eta's combinators are made aware of them through their result type — a typed `Error` in one branch ends the computation the way an exception would, and comes back as that same `Error`.

Two rules follow. A library converts I/O exceptions to `result` at its edge — once, where the operation is called — instead of letting them travel. And `try`/`with` stays as small as possible: around the one call that can raise the exception being converted, never around a region that also holds fibers, scopes or cancellation, because cancellation is an exception too (`Eio.Cancel.Cancelled`) and a wide handler turns an interruption into something else.

### Concurrency combinators

Each is a thin wrapper over Eio's own structured concurrency (`Fiber.both`/`all`/`any`, `Fiber.List.map`). None owns a switch: they run in the caller's cancellation context, so cancelling the caller cancels every branch, and Eio cancels and awaits the losers. One law: a combinator raises exactly what a body raises, returns exactly the `result` a body returns, adds nothing and swallows nothing; the interruption of losers is suppressed onto the primary outcome.

```ocaml
val par     : sw:Switch.t -> (unit -> ('a, 'e) result) -> (unit -> ('b, 'e) result) -> ('a * 'b, 'e) result
val all     : sw:Switch.t -> (unit -> ('a, 'e) result) list -> ('a list, 'e) result
val for_each : sw:Switch.t -> concurrency:int -> 'a list -> ('a -> ('b, 'e) result) -> ('b list, 'e) result
  (* fail-fast: the first typed Error or exception ends the computation; the rest are cancelled and awaited *)
val race       : sw:Switch.t -> (unit -> ('a, 'e) result) list -> ('a, 'e Cause.t) result
  (* first success wins; all-fail → Error (Concurrent causes) in input order, a lone failure unwrapped *)
val race_first : sw:Switch.t -> (unit -> ('a, 'e) result) list -> ('a, 'e) result
  (* first settled result of either kind *)
val with_background : sw:Switch.t -> (unit -> (unit, 'e) result) -> (unit -> ('a, 'e) result) -> ('a, 'e) result
  (* background is cancelled and awaited when the body settles; its own failure wins if it comes first *)
val Scope.supervised_error : sw:Switch.t -> ('e Scope.t -> ('a, 'e) result) -> ('a, 'e) result
val Scope.fork_error       : 'e Scope.t -> (unit -> ('b, 'e) result) -> ('b, 'e) Scope.fork
  (* the first Error from a fork or the body ends the scope with it *)
val timeout : clock:_ Eio.Time.clock -> Duration.t -> (unit -> ('a, [> `Timeout ] as 'e) result) -> ('a, 'e) result
  (* an alias of Eio.Time.with_timeout *)
```

`Scope.supervised_error` is Ox's `supervisedError`: a scope whose `fork_error` fibers return `result`s, where the first `Error e` ends the scope with `Error e` after every other fork was cancelled and awaited. It carries a typed error across forks by value, which is the direct-style answer to what `handled_effect` promised (`docs/modes.md`). Resources are Eio's: register the release with `Eio.Switch.on_release`; Eta has no resource module.

The Switch is passed explicitly, as Eio does; here it is only checked, the combinator owning nothing on it. Deadlines use `timeout`, never `race` against a sleep: race selects the first *success*.

### Schedules, retry, repeat

`Schedule.t` is pure data and survives from v1 unchanged; `Schedule.step` already takes `now_ms`. The drivers are ordinary loops over an explicit clock, so a mock clock makes them deterministic:

```ocaml
val retry  : clock:_ Eio.Time.clock -> ?policy:('a, 'e) Retry.policy -> (('a, 'e) result, _) Schedule.t -> (unit -> ('a, 'e) result) -> ('a, 'e) result
val repeat : clock:_ Eio.Time.clock -> ('a, 'o) Schedule.t -> (unit -> ('a, 'e) result) -> ('o, 'e) result
```

The thing to run is a thunk. That is the entire ergonomic cost of losing programs-as-values, and it is paid at exactly the places v1 already took an effect as an argument.

### Capabilities

Eio hands the operating system to a program as values — `clock`, `net`, `process_mgr`, `fs`, `domain_mgr` — and `Eio_mock` provides fakes. A function takes the specific values it uses (`~clock`, `~net`), never a whole environment, so its signature says what it can touch. Eta adds no capability layer, no ambient effects, and no `Runtime.t`.

### The application model

```ocaml
module type SERVICE = sig
  type t
  type config
  type deps
  type error
  val create : sw:Eio.Switch.t -> config -> deps -> (t, error) result
  val status : t -> Status.t
end

(* Config is a plain record with [@@deriving yojson]; the Door takes its derived
   decoder and encoder plus the environment function (ADR-0008). *)
let config : Leash.Config.t Eta_app.Config.t =
  { of_yojson = Leash.Config.t_of_yojson;
    yojson_of_t = Leash.Config.yojson_of_t;
    env = Leash.Config.env }

let () =
  Eta_app.run ~name:"leash" ~config ~validate:Leash.Config.validate
  @@ fun env config sw ->
  let open Result.Syntax in
  let* chrome  = Chrome.create  ~sw config.chrome  { process_mgr = env#process_mgr; clock = env#clock } in
  let* tabs    = Tabs.create    ~sw config.tabs    { chrome; clock = env#clock } in
  let query    = Eta_app.status_query [ Chrome.status chrome; Tabs.status tabs ] in
  let* control = Control.create ~sw config.control { tabs; fs = env#fs; status = query } in
  Eta_app.serve ~sw ()
```

The dependency graph is the order of the `let*` chain. Release order is the Switch's, reverse of acquisition. Tests create a Service with fake Deps. Status is read from the values themselves. The Door owns Env construction, config decoding through the config type's derived codec (ADR-0008), SIGINT/SIGTERM as interruption of the Program, rendering of the *full* Cause on failure, and the exit code. There is no registry, no reconciliation, no desired state: v1's component runtime became a shadow of the real data path within a month of adoption, and this model is what Pie converged on after deleting it.

### Testing

`eta_test` is `Eio_mock` plus assertions on `Exit` and `Cause`. A test runs the same code as production with a mock clock, a mock network, and scripted fakes at the seams the consumer's spec names. Virtual time controls sleeps, timeouts, retries and schedules; it does not control the operating system, so process and socket behaviour is tested with real fixtures, on purpose and separately.

## 5. Where effect handlers actually pay

OCaml 5's effect handlers are the reason direct style is possible at all — and in eta-next they are used *through Eio*, not beside it. The honest map:

- **Concurrency**: Eio's fibers *are* effect handlers (suspension is `perform`). Every `Fiber.fork`, `Switch.run`, `Promise.await` is effect-handler code you did not have to write. Eta adds no handler of its own for this.
- **Dynamic context** — the current span, log fields, a deadline — is what a handler-installed ambient value would express. Eio already provides it as fiber-local storage (`Fiber.create_key`, `Fiber.with_binding`), which crosses `fork` correctly; a home-made effect would not, because a handler installed outside a fork is not on the forked fiber's stack. Use the fiber-local key.
- **Domain-owned stepping** is where a first-class continuation is genuinely the right tool, and the test is one question: would any handler ever *hold* the continuation — resume later, out of order, more than once, or never? Generators and pull streams pass (yield). So does an agent loop whose decision step is owned by production, by a scripted test, or by a human inspector — the shape Jane Street found for Hardcaml testbenches, where the simulator owns the clock step. Config, errors, resources, retry and I/O all fail it: their handlers would resume at once, so they are parameters, `result`, Switches and Eio. ADR-0006 records the rule; every effect a consumer defines uses the local-token pattern so that "unhandled" is a compile error, stays in one fiber, and writes its three answers in its spec.
- **Typed errors as handlers** — Jane Street's `handled_effect`, where a failing function takes a `local` handler value and the mode system guarantees it is handled — is the most interesting alternative to `result` and the closest thing OCaml has to effect-safe typed exceptions. It is deferred, not rejected: as of 2026-09-26 every published `ppxlib_ast+ox` requires `ocaml < 5.3.0`, so on 5.4.0+ox neither `ppx_template`, `base` nor `handled_effect` can be installed at all. When that changes, the spike brief in `.scratch/research/handled-effect-errors/` on the v1 checkout says exactly what to prove: error unions, behaviour at `Fiber.fork` (a `local` handler cannot be captured by an escaping closure, so a forked fiber must re-install its own), cancellation, cleanup order, and cost.
- **Unhandled effects** are OCaml's real footgun: `perform` with no handler on the stack is a runtime exception, and the spike showed a forked Eio fiber hits exactly that. The local-token pattern turns it into a compile error, and the one-fiber rule keeps the token where the compiler can see it.

## 6. Migration

- `v1` is tagged and its branch stays alive for fixes to Pie, inn, nema, taumel, grip and p-doom.
- `eta-next` becomes `master` the day Leash milestone 1 runs on it.
- A consumer migrates whole when it next needs something from next; there is no bridge and no compatibility layer.
- Pure protocol code (HPACK, HTTP/1 parsing, HTTP/2 frames, WebSocket framing, the SQL DSL, AI wire types, TLS stubs) is copied file by file from v1 at the moment a consumer pulls it. Anything mentioning `Effect.t` is rewritten.
