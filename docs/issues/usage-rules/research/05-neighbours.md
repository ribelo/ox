# Neighbours: what other direct-style structured-concurrency ecosystems made into hard rules

Slot 05 of the eio-hardening research set. Subject: **Scala Ox, Kotlin coroutines, Java Loom
StructuredTaskScope/ScopedValue, Python Trio, Go context, Rust async** — which rules exist, how
each is enforced (compiler, lint, test, documentation), the exact lint identifiers, and what ox is
missing.

Method and evidence limits are stated in section 4. Every claim that is not my own reasoning
carries a URL; where a source states a rule but not its rationale, section 4 says so.

---

## Sources read

| Ecosystem | Primary sources |
|---|---|
| Scala Ox | ox.softwaremill.com (tour, structured concurrency, error handling, interruptions, resources, actors, rate limiter, OxApp, best practices) and the documentation source at github.com/softwaremill/ox (doc/, core/src/main/scala/ox/) |
| Kotlin | kotlinlang.org *Cancellation and timeouts*, *Coroutine exceptions handling*; developer.android.com *Best practices for coroutines in Android*; detekt *Coroutines Rule Set*; the AOSP lint-checks tree |
| Java | JEP 453, JEP 480, JEP 505; JDK 25 javadoc for StructuredTaskScope and ScopedValue; JEP 506 (ScopedValue finalized) |
| Trio | trio.readthedocs.io *reference-core* and *design*; flake8-async rules.html, README, usage page; trio-typing README |
| Go | pkg.go.dev/context, pkg.go.dev/cmd/vet, go.dev blog *Context*, go.dev blog *Contexts and structs*, x/tools lostcancel source |
| Rust | tokio select! docs, tokio sync::Mutex docs, clippy await_holding_invalid source |

Local copies of every fetched page are under /tmp/eio-hardening/05-neighbours/sources/.

---

## 1. Findings that apply to ox

Each finding: the rule, where it comes from, what it prevents, how it is enforced there.

### 1.1 Cancellation must be rethrown, never consumed

**Rule.** An operation that catches the cancellation-carrying exception either rethrows it or lets
it propagate; catching it and continuing is a bug.

**Where it comes from** (documentation, maintained by each project):

- Trio core manual, *Handling cancellation*: "You can catch `Cancelled`, but you shouldn't! Or more
  precisely, if you do catch it, then you should do some cleanup and then re-raise it or otherwise
  let it continue propagating" — https://trio.readthedocs.io/en/stable/reference-core.html
- Kotlin / Android guide, under "Watch out for exceptions": "To enable coroutine cancellation, don't
  consume exceptions of type `CancellationException` (don't catch them, or always rethrow them if
  caught). Prefer catching specific exception types like `IOException` over generic types like
  `Exception` or `Throwable`." — https://developer.android.com/kotlin/coroutines/coroutines-best-practices
- Kotlin own guide repeats it in every example: "// Always rethrow cancellation exceptions! throw e"
  — https://kotlinlang.org/docs/cancellation-and-timeouts.html
- Scala Ox, *Interruptions*: "When catching exceptions, care must be taken not to catch & fail to
  propagate an `InterruptedException`. Doing so will prevent the scope cleanup mechanisms to make
  appropriate progress, as the scope won't finish until all started threads complete."
  — https://ox.softwaremill.com/latest/structured-concurrency/interruptions.html

**What it prevents.** Exactly ox first historical bug class: a wide `try ... with _ ->` that
swallows `Eio.Cancel.Cancelled`, so a scope cleanup never makes progress (Scala Ox stated
consequence) or a cancelled operation reports success (Kotlin).

**How it is enforced there - and this is the interesting part, because each ecosystem picked a
different mechanism:**

| Ecosystem | Mechanism | Detail |
|---|---|---|
| Trio | **Compiler / class hierarchy** | `Cancelled` inherits from `BaseException`, "so that it won't be caught by catch-all `except Exception:` blocks" (reference-core). A broad handler literally cannot catch it. |
| Kotlin/Android | **Documentation** | The Caution box above; no lint cited on that page. |
| Kotlin | **Lint (detekt, opt-in)** | `SuspendFunSwallowedCancellation`, "Active by default: No", "Requires Type Resolution": "`Cancelled`/`CancelledError`-catching ... `CancellationException` should never be: caught and swallowed (even if logged), caught and propagated to external systems, caught and shown to the user; they must always be immediately rethrown in the same context." — https://detekt.dev/docs/rules/coroutines/ |
| Trio | **Lint (flake8-async, on by default)** | `ASYNC103` "no-reraise-cancelled"; `ASYNC104` "cancelled-not-raised": "Triggered on `return` or raising a different exception." — https://flake8-async.readthedocs.io/en/latest/rules.html |
| Scala Ox | **Documentation + code review** | The manual remedy is a style rule: "A good solution is to catch only non-fatal exception using `NonFatal`" (interruptions page). No static checker ships with Ox. |

### 1.2 Cleanup that suspends must be shielded and bounded - not merely protected

**Rule.** Work that must complete after cancellation (protocol farewell, flush, close) runs in a
region that ignores *outer* cancellation but still carries its own deadline.

**Where it comes from.** Trio canonical worked example (reference-core, *Cancellation semantics*):

> "Of course, if you really want to make another blocking call in your cleanup handler, Trio will let
> you ... To do this, create a new scope, and set its `shield` attribute to `True`:
> `with trio.move_on_after(TIMEOUT): ... finally: with trio.move_on_after(CLEANUP_TIMEOUT, shield=True) as cleanup_scope: await conn.send_goodbye_msg()`
> So long as you are inside a scope with `shield = True` set, then you will be protected from outside
> cancellations. Note though that this only applies to outside cancellations: if `CLEANUP_TIMEOUT`
> expires then `await conn.send_goodbye_msg()` will still be cancelled."

The mechanism it exists to defeat is Trio level-triggered cancellation: "once a block has been
cancelled, all cancellable operations in that block will keep raising `Cancelled`" - so a naive
cleanup inside a cancelled block is *itself* cancelled, and the cleanup never runs. Both quotes:
https://trio.readthedocs.io/en/stable/reference-core.html

**How it is enforced there.** By lint, for the dangerous half of it:

- flake8-async `ASYNC102` "await-in-finally-or-cancelled": "`await` inside `finally`,
  cancelled-catching `except:`, or `__aexit__` must have shielded cancel scope with timeout."
- detekt `SuspendFunInFinallySection`: "Report usage of suspending functions within a `finally`
  section that are not enclosed in a non-cancellable context. Without a non-cancellable context,
  these functions will not execute if the parent coroutine is cancelled" (opt-in, type resolution).
  — https://detekt.dev/docs/rules/coroutines/
- Kotlin guide gives the primitive, `NonCancellable`, with the reason "Without
  `withContext(NonCancellable)`, this function does not complete because the coroutine is canceled"
  — https://kotlinlang.org/docs/cancellation-and-timeouts.html

**Cost of `protect` alone.** Kotlin `NonCancellable` is the weak form: it ignores cancellation with
no deadline. Scala Ox is stronger - its scope finalizers run "in reverse registration order,
**uninterruptibly**" (`core/src/main/scala/ox/unsupervised.scala`, `runFinalizers`), and the same
uninterruptible wrapper is used for `useCloseable` release and for an actor close callback
("An optional callback that will be called uninterruptedly before the actor closes",
`core/src/main/scala/ox/channels/actor.scala`). Java Loom chose to *wait forever* instead: "The
`close` method always waits for threads executing subtasks to finish, even if the scope is
cancelled, so execution cannot continue beyond the `close` method until the interrupted threads
finish." — https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/StructuredTaskScope.html

### 1.3 A cancellation must never be *started* against work that is already cancelled

**Rule.** Starting a child, registering a waiter, or acquiring a slot must refuse (or immediately
cancel) when the surrounding scope is already cancelled.

**Where it comes from.** JEP 453 description of `shutdown()`: "A new subtask that is forked after a
call to `shutdown()` will be in the `UNAVAILABLE` state and will not be run." —
https://openjdk.org/jeps/453. Java javadoc adds a concrete owner-side rule: "`isCancelled` ... A
task with a lengthy "forking phase" (the code that executes before it invokes `join`) may use this
method to avoid doing work in cases where scope is cancelled by the completion of a previously forked
subtask or timeout."

**What it prevents.** A fiber or a protocol stage that begins a new frame after the scope ended -
the half-frame / lost-wake-up family: work that is born into a dead scope, or a waiter registered
after the notification it is waiting for.

### 1.4 Cancellation propagates to children by the *scope that owns their lifetime*, not by the scope visible at spawn time

**Rule.** A child cancellation set is fixed when it is spawned/attached, and is the set that
provably encloses its whole lifetime.

**Where it comes from.** Trio, *Child tasks and cancellation* (reference-core):

> "Note that what matters here is the scopes that were active when `open_nursery()` was called, not
> the scopes active when `start_soon` is called. So for example, the timeout block below does nothing
> at all: `async with trio.open_nursery() as nursery: with trio.move_on_after(TIMEOUT): # don't do this! nursery.start_soon(child)`"

The stated rationale is lifetime visibility: "In order for the timeout to apply to the child task,
Trio must be able to tell that its associated cancel scope will stay open for at least as long as the
child task is executing."

**How it is enforced there.** Trio runtime associates the task with the nursery cancel scope; the
mistake compiles and silently does nothing. **But the same principle is a compile-time refusal in
Scala Ox**: a resource scope "can only be started where no concurrency scope is visible - this is
verified at compile-time. The reason: forks started within a lexically visible resource scope could
outlive it, using resources after they have been released."
— https://ox.softwaremill.com/latest/utils/resources.html

This is the strongest form found anywhere in this survey: an ownership/lifetime rule that the type
system, not a linter, refuses.

### 1.5 Structured concurrency is enforced at run time by refusing the wrong *thread*, and by not implementing the unstructured interfaces

**Where it comes from.** Two separate mechanisms in the JDK:

- **Run-time structural refusal.** JEP 453: "attempts to call `fork(Callable)` from a thread that is
  not in the tree hierarchy of the scope ... will fail with an exception", and misuse of
  try-with-resources "may cause the scope methods to throw a `StructureViolationException`"
  (https://openjdk.org/jeps/453; JEP 505 repeats it as "attempts to call a `fork` method from a thread
  that is not the scope owner will fail with an exception" — https://openjdk.org/jeps/505). The
  JDK 25 javadoc makes the owner rule total: "`fork`, `join` and `close` methods may only be invoked
  by the owner thread ..., the `fork` method may not be called after `join`, the `join` method may
  only be invoked once, and the `close` method throws an exception after closing if the owner did not
  invoke the `join` method after forking subtasks."
- **Not implementing the unstructured API.** JEP 453: "`StructuredTaskScope` enforces structure and
  order upon concurrent operations. Thus it does not implement the `ExecutorService` or `Executor`
  interfaces since instances of those interfaces are commonly used in a non-structured way."

**What it prevents.** The leak class JEP 453 motivation lays out for `ExecutorService` + `Future`:
"Any code with a reference to a `Future` can join it ... even code in a thread other than the one
which obtained the `Future`. In effect, a subtask started by one task does not have to return to the
task that submitted it."

**Note on maturity.** `StructuredTaskScope` has been a preview API since JDK 21 (JEP 453) and was
still one in JDK 25 (JEP 505, "Fifth Preview", `Release 25`); the JDK 25 javadoc carries the banner
"preview API ... Preview features may be removed in a future release". `ScopedValue` was *finalized*
in JDK 25 (JEP 506, `Release 25`, "We here propose to finalize the scoped values API in JDK 25").
So: the scoped-value half is settled, the structured-concurrency half is not, after five years of
previews.

### 1.6 Cooperative cancellation needs checkpoints, a published list of them, and a lint that a cancel scope contains one

**Where it comes from.** Trio *Checkpoints* (reference-core) makes "checkpoint" a first-class,
documented property of a function, with rules for telling where they are: "Regular (synchronous)
functions never contain any checkpoints"; "If you call an async function provided by Trio and it
does not raise an exception, then it always acts as a checkpoint"; third-party code "can act as
checkpoints; if you see `await` ... then that might be a checkpoint". Reasons given: cancellation
latency, and "since Trio is a cooperative multi-tasking system where the only place the scheduler can
switch tasks is at checkpoints, it will also prevent the scheduler from fairly allocating time between
different tasks".

**Enforced by lint, five rules:** `ASYNC100` "cancel-scope-no-checkpoint" ("A timeout context does
not contain any checkpoints. This makes it pointless, as the timeout can only be triggered by a
checkpoint"), `ASYNC910` "async-function-no-checkpoint", `ASYNC911` "async-generator-no-checkpoint",
`ASYNC912` "cancel-scope-no-guaranteed-checkpoint" ("A timeout/cancelscope has cancel points, but
they are not guaranteed to run"), `ASYNC913` "indefinite-loop-no-guaranteed-checkpoint" ("An
indefinite loop (e.g. `while True`) has no guaranteed checkpoint. This could potentially cause a
deadlock"). — https://flake8-async.readthedocs.io/en/latest/rules.html

detekt's nearest equivalent is `SleepInsteadOfDelay` (blocking sleep in a coroutine).

**The full rule set, for the record.** The page carries 47 codes: `ASYNC1xx` (general semantics -
on by default), `ASYNC2xx` (blocking sync calls in async functions), `ASYNC300` (asyncio task
reference), `ASYNC4xx` (ExceptionGroup), and `ASYNC9xx` - which the usage page lists as
"Defaults to ASYNC9" for the *disable* option while *enable* "Defaults to ASYNC", i.e. **the 9xx rules are off by default and must be
enabled**: ASYNC900 unsafe-async-generator, ASYNC910 async-function-no-checkpoint, ASYNC911
async-generator-no-checkpoint, ASYNC912 cancel-scope-no-guaranteed-checkpoint, ASYNC913
indefinite-loop-no-guaranteed-checkpoint. Two more codes matter for ox but are not checkpoint rules:
`ASYNC120` "await-in-except" - "If this checkpoint is cancelled, the current active exception will be
replaced by the `Cancelled` exception, and cannot be reraised later" - and `ASYNC128`
"task-status-never-started". Autofix exists for ASYNC100, ASYNC910, ASYNC911 and ASYNC913.
Codes were renamed from `TRIOxxx` to `ASYNCxxx` wholesale.


### 1.7 The uninterruptible tail is enumerated, with a workaround for each entry

**Where it comes from.** Scala Ox *Interruptions* page is a maintained catalogue: interruptible
operations (JDK blocking ops, blocking socket I/O on virtual threads per JEP 444, `Process.waitFor`,
Ox own channel operations), destructively-interruptible operations (NIO channels - "the interrupt
**closes the channel**"; with a cited OpenJDK bug, `FileChannel` interruption "has been observed to
return normally while silently closing the channel", https://bugs.openjdk.org/browse/JDK-6979009),
and a list of known **uninterruptible** operations: classic `java.io` stream reads and writes
("closed as Won't Fix", https://bugs.openjdk.org/browse/JDK-4514257), blocked console writes,
socket I/O on platform threads, DNS resolution, JDBC calls, `synchronized` and `ReentrantLock.lock()`,
reading a subprocess output streams, memory-mapped page faults.
— https://ox.softwaremill.com/latest/structured-concurrency/interruptions.html

**The workaround, and its price.** Scala Ox ships `abandonOnInterrupt`, `abandonOnInterruptReads`,
`abandonOnInterruptWrites` (same page): the blocking operation is delegated to a *detached* thread -
"an unmanaged virtual thread, running outside of any concurrency scope, which is never joined" -
while the caller awaits interruptibly; on interruption the operation is abandoned and its result
discarded. The page states the trade-off plainly: "a (cheap, virtual) thread is potentially left
behind, in exchange for interruptibility", and "abandoned operations keep running - including their
side effects (e.g. an abandoned JDBC query keeps executing on the server)".

Java Loom has no equivalent: the javadoc only answer to a subtask that does not respond to
interrupt is that it "may delay the closing of a scope indefinitely".

### 1.8 "Cancellation safety" is a per-operation documented property: dropping an incomplete future and recreating it must be a no-op

**Where it comes from.** tokio `select!` documentation, section Cancellation safety:
https://docs.rs/tokio/latest/tokio/macro.select.html

> "If you have a future that has not yet completed, then it must be a no-op to drop that future and
> recreate it."
> "When using `select!` in a loop to receive messages from multiple sources, you should make sure
> that the receive call is cancellation safe to avoid losing messages."

tokio maintains the list in three buckets inside the macro documentation: safe
(`mpsc::Receiver::recv`, `broadcast::Receiver::recv`, `watch::Receiver::changed`,
`TcpListener::accept`, `AsyncReadExt::read`, `AsyncWriteExt::write`, `StreamExt::next`, ...); not
safe, "can lead to loss of data" (`read_exact`, `read_to_end`, `read_to_string`, `write_all`);
not safe "because they use a queue for fairness and cancellation makes you lose your place in the
queue" (`sync::Mutex::lock`, `RwLock::read`/`write`, `Semaphore::acquire`, `Notify::notified`).
Per-method, the same section appears in the API page: `Mutex::lock` - "Cancelling a call to `lock`
makes you lose your place in the queue." — https://docs.rs/tokio/latest/tokio/sync/struct.Mutex.html

**How it is enforced there.** **Documentation only.** There is no Rust lint for cancellation safety;
the survey of clippy registry found no lint for it. What Rust *does* enforce mechanically are two
adjacent hazards, which are the same shape ox needs:

- `clippy::await_holding_lock` - "Checks for calls to `await` while holding a non-async-aware
  `MutexGuard`" (source: `clippy_lints/src/await_holding_invalid.rs`, lint declared `suspicious`;
  https://rust-lang.github.io/rust-clippy/master/index.html#await_holding_lock).
- `clippy::await_holding_refcell_ref`, and the configurable
  `clippy::await_holding_invalid_type` ("Allows users to configure types which should not be held
  across await suspension points") - same source file.
- `clippy::let_underscore_future` - "Checks for `let _ = ` where the resulting type of expr
  implements `Future`", i.e. a future that is created and never polled.

### 1.9 Prompt cancellation: a cancelled operation returns no value

**Where it comes from.** Kotlin guide names it: "`withContext(Dispatchers.IO)` cooperates with
cancellation and prevents `updateUI()` from running if the `leaveScreen()` function cancels the
coroutine before it returns the contents of the file" - the *value* is not delivered. Trio has the
same via level-triggering.
— https://kotlinlang.org/docs/cancellation-and-timeouts.html

The counter-hazard is stated too: "While prompt cancellation prevents using values after they are no
longer valid, it can also stop your code while an important value is still in use, which might lead
to losing that value." Kotlin remedy is a *shape*: hold the resource in a variable declared outside
the suspendable region and close it in `finally`, so cancellation cannot strand it.

### 1.10 Error groups: always wrap, even a single error

**Where it comes from.** Trio *Historical Note* (reference-core), which is a rare case of a
maintainer documenting a design *reversal* with the production evidence:

> "In early versions of Trio ... some APIs would therefore raise single exceptions, and only wrap
> concurrent exceptions in the old `trio.MultiError` type if there were two or more. Unfortunately,
> the results were not good: calling code often did not realize that some function could raise a
> `MultiError`, and therefore handle only the common case - with the result that things would work
> well in testing, and then crash under heavier load (typically in production). `asyncio.TaskGroup`
> learned from this experience and always wraps errors into an `ExceptionGroup`, as does `anyio`, and
> as of Trio 0.25 that is our default behavior too."

### 1.11 Scope-bound lifetimes as the *reason* for lifecycle correctness (Scala Ox RateLimiter, Actor, Flow, OxApp)

Not a rule so much as a pattern ox can copy by construction: a component that owns background work
is created *inside* a scope and has no teardown API, because scope end is teardown.

- `RateLimiter`: "A rate limiter must be created within an `Ox` concurrency scope, as a background
  fork is created, to replenish the rate limiter. Once the scope ends, the rate limiter is stops as
  well." The source confirms the mechanism: `RateLimiter.apply` is `forkDiscard(update())` where
  `update` loops on `Thread.sleep` - interruptible, so cancellation ends it.
  — https://ox.softwaremill.com/latest/utils/rate-limiter.html and
  `core/src/main/scala/ox/resilience/RateLimiter.scala`
- `Actor`: created with `Actor.create` inside a scope; the close callback is run `uninterruptibly`;
  fatal exceptions (including interruptions) end the actor and propagate to the enclosing scope.
  — https://ox.softwaremill.com/latest/utils/actors.html
- `OxApp`: "When the application receives a SIGINT/SIGTERM ... the root scope (and hence any child
  scopes and forks) are interrupted. This allows for a clean shutdown" - plus a documented
  counter-example: calling `System.exit` inside an Ox-managed fork "will cause a deadlock with the
  cleanup process" (issue #368), bounded by a `shutdownTimeout` setting (default 10s).
  — https://ox.softwaremill.com/latest/utils/oxapp.html
- `Flow`: the documented error rule is the same law as ox combinators - merge "properly handling the
  failure of either branches" - and the *Error propagation* section of the streaming docs.
  — https://ox.softwaremill.com/latest/streaming/index.html

### 1.12 Best practices that are the same rule in several ecosystems at once

Scala Ox best-practices page (https://ox.softwaremill.com/latest/other/best-practices.html) states
four rules whose counterparts are mechanical elsewhere:

| Scala Ox rule | Same rule elsewhere |
|---|---|
| "Make scopes as small as possible" | Trio: "The nursery will remain open until all child tasks have completed" - the scope *is* the lifetime |
| "Use `using Ox` sparingly" (passing the capability "gives the method the power to start new threads - which can be a dangerous tool!") | ox own `Spawner` spec (delivery-map row 64); Android "Avoid `GlobalScope`" |
| "Avoid returning `Fork`": "if you call two methods which return a `Future`, they will run concurrently, even though you might have never intended that" | JEP 453: not implementing `ExecutorService` / not returning `Future` |
| "Integrate with callback-based APIs using channels" | Trio: "Task spawning is always explicit. No callbacks, no implicit concurrency, no futures/deferreds/promises" (design.html) |

### 1.13 Where the ecosystems *chose not to* build a rule

Worth recording because ox will be tempted:

- **Rust has no cancellation-safety lint and no language support** - the property is carried entirely
  by documentation on the future own page plus three lints for adjacent hazards (1.8).
- **Java keeps the cancellation mechanism unchanged**: JEP 453 non-goals - "It is not a goal to
  replace the existing thread interruption mechanism with a new thread cancellation mechanism." The
  entire structured-concurrency benefit is delivered by *confining* interruption, not by replacing it.
- **Trio explicitly gives up control over one region**: the async-generator restriction ("You may not
  write a `yield` statement that suspends an async generator inside a `CancelScope` or `Nursery` that
  was entered within the generator") is documented with the admission that Trio "is not able to detect
  all such cases, so sometimes you will get an unhelpful `TrioInternalError`. (And sometimes it will
  seem to work, which is probably the worst outcome of all...)". The linter `ASYNC101`/`ASYNC119`
  catches the static part. — reference-core; flake8-async rules page.

---

## 2. Things ox should adopt

Ranked by (bug class covered x certainty of enforcement) / cost. "Cost" is what it takes to make the
rule *decidable*, not to write the prose.

### Rank 1 - `no-swallowed-cancel`: a lint that decides 1.1, with the two shapes Kotlin linter distinguishes

**Shape in ox.** One page `docs/rules/no-swallowed-cancel.md` plus a lint pass over ox and its
consumers that flags, in files that may suspend:

1. a handler that binds `Eio.Cancel.Cancelled` and does not re-raise it (**ASYNC104** shape -
   "Triggered on `return` or raising a different exception");
2. `with _ ->` / `with exn ->` / `with _exn ->` whose body does not re-raise the bound value
   (**ASYNC103** shape);
3. a handler that catches `Cancelled` and *then* suspends before rethrowing (detekt: "caught and
   propagated to external systems", "caught and shown to the user").

**Precedent that the check is implementable statically:** `ASYNC103`/`ASYNC104` and detekt
`SuspendFunSwallowedCancellation` both do exactly this. Note ox own inventory already counted the
sites: "five catch-all handlers" in `lib/` (row 66 spec, `docs/issues/raw-concurrency-gate`).

**Cost.** Low-to-medium. A syntactic pass over an OCaml AST can see every shape above; the limit is
that OCaml cannot statically prove a handler body cannot raise a cancel - so, like detekt, the rule
is "does not re-raise", not "is safe". Document that limit (usage-rules story 4 asks for exactly this
disclosure).

### Rank 2 - `finalizer-must-not-suspend-unshielded`: gate the `Fun.protect` / `Switch.on_release` body

**Shape in ox.** The lint flags a `Fun.protect ~finally` (or a `Switch.on_release` callback) that
suspends, unless the body is wrapped in the protected form or explicitly allow-listed with a reason.
This is clippy `await_holding_lock` move applied to finalizers: the checker does not understand types,
it matches the *syntactic* shape of "a suspending call inside the finally body", which is exactly how
clippy finds a guard held across `await`.
— https://rust-lang.github.io/rust-clippy/master/index.html#await_holding_lock

**What it prevents.** ox second historical class, plus one real JVM trap worth quoting in the rule
page: an interrupted `FileChannel` read "has been observed to return normally while silently closing
the channel" (https://bugs.openjdk.org/browse/JDK-6979009) - i.e. a finalizer whose suspension
succeeds in the wrong way.

**Cost.** Medium. 33 existing `Fun.protect` sites (row 66 spec) must be classified; the check needs an
allow-list with a reason per entry, exactly like `scripts/caps-gate` already does.

### Rank 3 - `uninterruptible-surface`: publish the list, ship the wrapper, test the wrapper

**Shape in ox.** Three parts, mirroring Scala Ox (1.7):

1. `docs/rules/uninterruptible.md`: for each blocking operation ox packages actually use (classic
   OCaml blocking I/O, Unix domain sockets, process pipes, subprocess waits, memory-mapped reads),
   state interruptible / destructively-interruptible / uninterruptible, with the citation.
2. A wrapper in `lib/ox/` (sibling of the `abandonOnInterrupt*` family) that runs an uninterruptible
   operation on a detached domain/fiber and awaits the result interruptibly, with an `on_abandon`
   cleanup argument.
3. **A deterministic test shape** (the part that makes it a rule rather than prose): a test that a
   scope cancellation *returns* while a fiber is blocked in an uninterruptible operation, and that
   abandoned work is either cleaned up or explicitly documented as leaked. Scala Ox has these as
   tests - `core/src/test/scala/ox/AbandonOnInterruptTest.scala`, including "abandonOnInterruptReads
   should let a scope cancel a fork blocked on an uninterruptible read".

**Cost.** Medium-high: the wrapper is real code (detached thread + rendezvous channel +
close-on-abandon), and the leak is a deliberate, documented trade-off. Do it for one operation first
(subprocess pipes or stdin) so the shape gets reviewed before it spreads.

### Rank 4 - `cancel-safety-clause` in every `.mli` val that can partially apply an effect

**Shape in ox.** Extend the existing per-interface convention ("Cancellation and finalizers:" sections
already appear across `lib/*/*.mli`) from *does this suspend* to the tokio property: **if this
operation is cancelled midway, can the caller re-run it?** tokio definition is the sentence to quote:
"If you have a future that has not yet completed, then it must be a no-op to drop that future and
recreate it." Three-valued, like tokio lists: *safe*, *not safe - loses data*, *not safe - loses
queue position". — https://docs.rs/tokio/latest/tokio/macro.select.html

**What it prevents.** ox fifth and sixth historical classes: "half frames in a protocol parser" and
"a lost wake-up". A cancelled `read_frame` that leaves half a frame consumed is a cancellation-safety
bug, and today nothing in the tree names it as one.

**Cost.** Low per file, high in aggregate (it is a documentation sweep over every suspending val).
The mechanical half - usage-rules story 6's check, "fails on a new or changed `val` whose doc
comment states none of it" - is the cheap enforcement; a full sweep can follow per package.

### Rank 5 - `already-cancelled-refuses-new-work`

**Shape in ox.** A documented rule plus a test shape: any ox API that starts work in a scope
(`Scope.fork*`, channel send with a registered waiter, supervisor admission, actor enqueue) must either
refuse when the scope is already cancelled or cancel the newcomer immediately; the test asserts it for
each such API. Java does this by construction (`UNAVAILABLE`, 1.3); ox `fork_error` already has the
Eio rule ("If the scope is already ending the fiber is not started") - the gap is that this is not
stated as a *rule with a check* for ox own combinators and for the packages built on them.

**Cost.** Low to state and test; medium if any API turns out not to satisfy it today.

### Rank 6 - a shield-with-deadline primitive

**Shape in ox.** A `Shield.with_deadline : Duration.t -> (unit -> 'a) -> ('a, [> `Timeout]) result`
(or an option-returning variant) over `Eio.Cancel.protect`, so that "ignore outer cancellation but
still bound yourself" is one call, not a hand-rolled combination. Trio argument for the deadline half
is quoted in 1.2; Java counter-example (close waits forever) is the argument against `protect` alone.

**Cost.** Low. Note the dependency: `Ox.Cancel.protect` is already a spec item (row 65,
`docs/issues/ox-mutex`), so this rides on it.

### Rank 7 - `checkpoint` vocabulary and the `ASYNC100` / `ASYNC912` / `ASYNC913` family

**Shape in ox.** Adopt Trio word for it (a *checkpoint* is a point where cancellation can be observed)
and the three mechanical checks that have no ox counterpart:

- `timeout f` where `f` contains no suspension point -> the timeout can never fire (`ASYNC100`);
- an indefinite `while true` loop with no suspension on every path -> cancellation latency and,
  under a cooperative single-threaded scheduler, starvation (`ASYNC913`);
- a cancel scope whose checkpoint is conditional -> not guaranteed (`ASYNC912`).

**Cost.** Medium (needs the AST to reason about "path contains a suspending call"), and ox package
set has few cancel scopes today. Adopt `ASYNC100` and `ASYNC913` first; they are the two with a
straightforward syntactic test.

### Rank 8 - test shapes for each of the four classes (the "row 85 simulation" contract)

Not a new rule but a placement decision: every rule above that cannot be gated should name its
deterministic case. The neighbours give three reusable test shapes:

1. **cancel-during-cleanup**: cancel a scope while a finalizer is suspended; assert the finalizer
   finishes and the release is observed (Scala Ox `AbandonOnInterruptTest`, `UtilTest`
   "uninterruptible should complete the body and then rethrow an interruption received while waiting").
2. **prompt cancellation delivers no value**: assert a cancelled operation returns no partial result
   (Kotlin 1.9) - for a protocol stage, assert the frame boundary is intact.
3. **already-cancelled spawn refuses**: assert no new fiber/waiter is created after cancellation (1.3).

**Cost.** Low per shape, and these are exactly the cases row 85 (`docs/issues/simulation/01-simulation.md`)
already promises to carry.

---

## 3. Things that look relevant but do not apply

| Candidate | Source | Why it does not apply to ox |
|---|---|---|
| Rust `select!` cancellation safety as a *cancellation* rule | https://docs.rs/tokio/latest/tokio/macro.select.html | The property exists because dropping a future cancels it and `select!` in a loop recreates it. Eio does not cancel by dropping a value: ox cancellation is a switch/fiber event. The *documentation convention* transfers (Rank 4); the rule as a cancellation mechanism does not. |
| `clippy::let_underscore_future` | clippy source | Rust-specific hazard: an unpolled future does nothing. An OCaml expression with an effect runs when evaluated. |
| Kotlin `NonCancellable` *without* a deadline | https://kotlinlang.org/docs/cancellation-and-timeouts.html | Superseded by the shield-with-deadline form (Rank 6). Adopting the weaker form alone would let a finalizer hang forever, which Java JEP shows is a real outcome. |
| Go `context` as a parameter that must be threaded | https://pkg.go.dev/context | "Do not store Contexts inside a struct type; instead, pass a Context explicitly to each function that needs it ... The Context should be the first parameter, typically named `ctx`." This exists to make cancellation *visible* where there is no lexical scope. Eio cancellation is already lexical and fiber-bound, and ox passes switches explicitly. A `ctx` parameter everywhere would be a second, weaker cancellation channel. |
| Go `lostcancel` shape (a cancel function that must be called on every control-flow path) | x/tools/go/analysis/passes/lostcancel | Go cancel function is a *leak* (a timer and a parent reference) that must be released manually. In Eio the equivalent object is the switch, and the resource leak is already covered by owning handles (row 62). Nothing in ox is "created and must be called later, else it leaks forever" in the same sense. |
| JEP 506 `ScopedValue` | https://openjdk.org/jeps/506 | ox already has `Eio.Fiber.with_binding` and `Ox_observability.Context` for fork-locals. The interesting JDK property - bindings are captured when the scope is created and inherited by every subtask - is a restatement of "inherited by forks", which ox gets from Eio. |
| Go structural convention rules | https://go.dev/blog/context | Passing `context.TODO` when unsure, not passing nil, `WithValue` only for "request-scoped data that transits processes and APIs" - conventions for a pervasive implicit parameter. ox has no such parameter. |
| Trio async-generator restriction | reference-core, *Cancel scopes and nurseries* | Exists because a Python generator can suspend outside its lexical scope. ox resource scopes have no generator equivalent, and Scala Ox answer to the analogous problem is the compile-time rule in 1.4 - which ox already shares. |
| detekt `InjectDispatcher`, `GlobalCoroutineUsage`; Android ViewModel / dispatcher-testing guidance | detekt; developer.android.com | Application-architecture advice for Android. ox equivalents are its own (capabilities, `Spawner`, no `GlobalScope` to avoid). |
| flake8-async `ASYNC200`-`ASYNC251` (blocking HTTP, subprocess, `open`, `os.path`, `input`, `time.sleep`) | flake8-async rules page | Python-specific: they exist because blocking the *single* event-loop thread stalls everything. ox tree runs on a multi-domain runtime with an explicit blocking package (`ox_blocking`), so the rule has a different reason and is already covered by `caps-gate` and the blocking budget. |
| `ASYNC111` (context manager opened inside a nursery passed to `start_soon`) and `ASYNC113`/`ASYNC114` (`start_soon` in `__aenter__`) | flake8-async rules page | Trio/anyio API-shape rules with no ox counterpart: ox has no `start_soon`-style API that hands a context-managed variable to a task. |
| Android Lint as the source of the cancellation rule | AOSP lint-checks | I could not find one (see section 4). The Kotlin-ecosystem *mechanical* enforcement I could actually verify is detekt, not Android Lint. |

---

## 4. What I could not find out

Stated as absence, not filled in. Each item below is the limit of my evidence, not a claim about the
ecosystem.

1. **No Android Lint rule for rethrowing `CancellationException` was found.** I listed all 349 entries
   of the AOSP `lint-checks` source directory (`android.googlesource.com/platform/tools/base`,
   `mirror-goog-studio-main`); the only names matching *cancell* / *coroutine* / *suspend* / *job* were
   `ControlFlowGraph.kt`, `DataFlowAnalyzer.kt` and `JobSchedulerDetector.java` - none of which is this
   rule. GitHub code search for a rule named `RethrowCancellationException` was unavailable to me (the
   API requires authentication). I therefore cannot say whether such an inspection exists in the
   Kotlin/IDEA plugin, in a Google-internal lint check, or anywhere else; I verified only that it is
   not in the public AOSP lint-checks directory I listed.
2. **The rationale for several rules is not published.** flake8-async rules page states what each
   check catches and, for some, why (e.g. `ASYNC100`: "This makes it pointless, as the timeout can
   only be triggered by a checkpoint"), but for others it only names the hazard (`ASYNC910`-`ASYNC913`
   have no rationale text). detekt `SuspendFunInFinallySection` states the consequence but not the
   design discussion. **I am not claiming a documented argument where I only found a documented rule.**
3. **Whether a Trio `Cancelled` can cross a task boundary is not answered by the documentation I
   read.** The reference says a `Cancelled` "knows which block it belongs to" and that a scope sees the
   exceptions its children raise, which implies the machinery exists; I found no rule about catching a
   `Cancelled` belonging to another task, and I am not asserting one either way.
4. **I did not read Scala Ox release notes or its GitHub issues corpus**, only the documentation source
   and the relevant `core/src` files. Where Scala Ox manual cites a bug or issue (JDK-6979009,
   JDK-4514257, Ox issue #368) I quote the citation rather than the underlying thread.
5. **Whether Kotlin has a sanctioned exception to "always rethrow" is unverified.** The guide and the
   Android page both state it with no exception, but I did not read kotlinx.coroutines source or its
   issue tracker. detekt rule text points at `Kotlin/kotlinx.coroutines#3658` as a reason people need a
   workaround, which suggests the doctrine is easier to state than to obey - but I did not read that
   issue.
6. **The full clippy lint registry could not be verified from the public JSON endpoints**
   (`rust-lang.github.io/rust-clippy/master/lints.json` and `index.json` both returned HTTP 404 in this
   session). The lint identifiers, categories and doc texts below are verified from the
   `declare_clippy_lint!` blocks in `rust-lang/rust-clippy:clippy_lints/src/await_holding_invalid.rs`;
   the documentation anchor is verified only for `#large_futures`, which the crawled `index.html`
   contained. `let_underscore_future` is quoted from the crawled index text; I did not open its own
   documentation anchor.
7. **I did not measure or verify any of these rules against ox tree.** The counts in section 2 (five
   catch-all handlers, 33 `Fun.protect` sites) are quoted from ox own row 66 spec, not re-derived by
   me.
8. **Scala Ox "table of contents as of 2026-09-29" is the version ox floor uses** (ADR-0009); the
   documentation I read is the current `latest` build. If Scala Ox has changed an item since that
   date, section 1 describes the current text, not the pinned snapshot.

---

## Summary

The six ecosystems converge on the same small set of rules, but each made a *different* thing hard:

- **Trio** made the swallowed-cancellation bug unrepresentable for the common case by putting
  `Cancelled` under `BaseException`, and then wrote 47 lint rules (`ASYNC100`-`ASYNC913`; the
  cancellation/checkpoint ones in `ASYNC1xx`, and the checkpoint rules `ASYNC900`-`ASYNC913` off by
  default) for everything the class hierarchy could not reach: cancel-scope-without-checkpoint,
  await-in-finally, no-reraise-cancelled, cancelled-not-raised, await-in-except, unsafe yields,
  missing checkpoints.
- **Kotlin** documents the doctrine and gets mechanical enforcement from detekt opt-in,
  type-resolution-requiring `SuspendFunSwallowedCancellation` and `SuspendFunInFinallySection`;
  Android documents the same doctrine with no lint I could verify.
- **Java Loom** made structure a run-time refusal (an owner thread, a single `join`, no `Future`, no
  `ExecutorService`) and made "ill-behaved" subtasks the documented, unbounded danger; after five
  previews it is still a preview, while `ScopedValue` is final.
- **Scala Ox** wrote the best *prose* catalogue of the problem - interruptible, destructively
  interruptible, uninterruptible, each with its workaround - and put two real rules in the compiler (no
  `fork` outside a scope; no concurrency scope visible where a resource scope starts).
- **Go** puts cancellation in a parameter and relies on conventions plus one vet check (`lostcancel`);
  most of its rules do not transfer.
- **Rust** has no cancellation-safety enforcement at all, and says so by writing the property on every
  API page; its lints catch adjacent hazards (a guard held across `await`, an unpolled future).

For ox, the two rules that are currently *documented but undecided* - no swallowed cancel, and no
suspending unshielded finalizer - are the two the neighbours decided mechanically. Neither needs types:
`ASYNC103`/`ASYNC104` and `clippy::await_holding_lock` are both syntactic checks over the suspending
region, exactly the kind of check an OCaml AST pass can make. The genuinely type-level rule, and the one
ox is closest to already having, is the ownership/lifetime refusal Scala Ox states in 1.4 - which ox has
in embryo through `Scope.supervised_error` switch discipline and rows 61-71.

Report: `/tmp/eio-hardening/05-neighbours/REPORT.md`

