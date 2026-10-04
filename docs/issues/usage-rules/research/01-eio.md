# How the Eio community hardens the things ox takes from Eio

**Slot:** 01-eio · **Date:** 2026-10-04 · **Author:** research subagent (read-only; nothing in any repository was modified)

## Scope and method

**What I read, and how.**

* **Eio 1.6 source, primary.** The opam release tarball for eio 1.6 was already in the Nix store
  (/nix/store/5bn763shmqncpznn03wl6xyvknrx1r15-eio-1.6.tbz), extracted to
  /tmp/eio-hardening/01-eio/eio-1.6-src/eio-1.6/. All file:line citations below refer to that extraction.
  This is the exact version ox builds against, so quotes are version-accurate. Where I give a
  github.com/ocaml-multicore/eio/blob/main/... URL I verified the *text* against the 1.6 tarball, not against
  the current content of that URL; the URL is the canonical place a reader can find the file.
* **Published API docs.** Two hosts serve the same odoc output, and both return HTTP 200:
  `https://ocaml-multicore.github.io/eio/` — which is what the project itself points at (`eio.opam` line 9 is
  `doc: "https://ocaml-multicore.github.io/eio/"`, and the README's link block at line 1864 is
  `[Eio API]: https://ocaml-multicore.github.io/eio/`; both verified by fetching them from `main`) — and
  `https://ocaml.github.io/odoc/eio/`, the odoc-generated mirror that search engines surface. **Most URLs I cite
  in this report use the `ocaml.github.io/odoc/` form, because that is the one I fetched and quoted; the same
  pages exist under `ocaml-multicore.github.io/eio/`.** I fetched the `Eio.Cancel` page and confirmed the text is
  byte-identical to the 1.6 `.mli`; other pages I checked for existence (HTTP 200) and matched against the 1.6
  `.mli` text I have locally.
* **GitHub issues and PRs**, via the authenticated gh CLI (gh api search/issues, gh api repos/.../issues/N).
  Bodies and comments are quoted verbatim.
* **Discuss threads**, via the Exa crawler.
* **Real consumers**, fetched as source: mirage/capnp-rpc (tarball of master), mirage/ocaml-cohttp (tarball of
  master), ocaml-multicore/lwt_eio (lib/lwt_eio.ml), semgrep/semgrep (two files).
* **Eio's own test and tooling directories**: tests/, lib_eio/tests/dscheck/, lib_eio/mock/, stress/, fuzz/,
  .github/workflows/main.yml, HACKING.md, doc/multicore.md, doc/rationale.md.

**What I did not do.** I did not run any Eio code. I did not read the Eio mailing list, Discord, or the
ocaml/ocaml tracker beyond what issues link to. Absences I report are absences *in the sources I searched*;
I say what I searched each time.

---

# 1. Findings that apply to ox

Each finding is: **rule → source (URL, kind) → what it prevents → how it is enforced there.**
Claims that are mine, not a source's, are marked *[inference]*.

## 1.1 Cancellation

### F1. A Cancelled exception can be swallowed; re-check cancellation whenever you catch and intend to ignore

> "It is possible the exception will get lost (if something catches it and forgets to re-raise). It is also
> possible to get this exception even when not cancelled, for example by awaiting a promise which another fiber
> has resolved to a cancelled exception. When in doubt, use `Fiber.check ()` to find out if your fiber is really
> cancelled. Ideally this should be done any time you have caught an exception and are planning to ignore it,
> although if you forget then the next IO operation will typically abort anyway."

* **Source:** `Eio.Cancel` module documentation — <https://ocaml.github.io/odoc/eio/eio/Eio/Cancel/index.html>
  (official API docs; fetched and quoted verbatim). Same text in source:
  `lib_eio/core/eio__core.mli:542-547` (eio 1.6).
* **Prevents:** ox's known "swallowed `Eio.Cancel.Cancelled` by a wide `try ... with _ ->`" class. A fiber that
  catches broadly, logs, and continues runs on after its parent has already failed, so the scope never drains.
* **Enforced there:** **documentation only** — there is no lint, ppx or compiler support. The one real-project
  instance I found of the rule being followed in code: `mirage/capnp-rpc`'s `leak_handler.ml` calls
  `Eio.Fiber.check ()` inside its `with ex ->` handler *before* logging, so a cancellation that arrives while it
  is handling an unrelated exception is not mistaken for a reportable error —
  <https://github.com/mirage/capnp-rpc/blob/master/capnp-rpc/leak_handler.ml> (source code, maintainer's own library).

### F2. Quick cleanup while cancelled is fine; anything that may block is not

> "When handling a `Cancelled` exception, quick clean-up actions (such as releasing a mutex or deleting a
> temporary file) are OK, but operations that may block should be avoided. For example, a network connection
> should simply be closed, without attempting to send a goodbye message."

* **Source:** same `Eio.Cancel` doc page (official docs); `lib_eio/core/eio__core.mli:549-553`.
* **Prevents:** ox's "finalizer that suspends while already cancelled". This is the *rule* half of the answer.
* **Enforced there:** documentation. The *exception* to the rule is what makes it usable — see F3.

### F3. If cleanup must suspend, that suspension must be under Cancel.protect — and there is a test for it

Eio's own condition variable must re-take a lock while it is being cancelled. It does that with a
non-cancellable lock:

```ocaml
(* lib_eio/condition.ml:10-11 *)
let lock_protected m =
  Cancel.protect (fun () -> Eio_mutex.lock m)
```

used on **both** the success and the exception path of `await_generic` (`lib_eio/condition.ml:31-36`).

* **Source (official doc):** `Eio.Condition.await` — "You should lock [mutex] before testing whether the condition
  is true, and leave it locked while calling this function. It will be unlocked while the fiber is waiting and
  locked again before returning **(it is also locked again if the wait is cancelled)**."
  <https://ocaml.github.io/odoc/eio/eio/Eio/Condition/index.html>
* **Source (maintainer, PR body):** talex5, PR #487 "Fix Condition.await bug when cancelling":
  > "`Condition.await` needs to re-acquire the lock when cancelled. However, if another fiber is holding the lock
  > then this operation must wait and would itself get cancelled. … It's a little annoying that we have to do a
  > non-cancellable wait during cancellation, since typically we only need the lock so we can call unlock on it
  > again immediately."

  <https://github.com/ocaml-multicore/eio/pull/487> (PR description by maintainer; issue reported by @polytypic).
* **Source (test, this is the important part):** `tests/condition.md` section **"Cancelling while the mutex is
  held"**, whose preamble is literally the rule:

  > "`await` must always re-acquire the lock, and that lock operation must be non-cancellable"

  The test runs under `Eio_mock.Backend.run`, forks a fiber that locks and awaits, then in the main fiber takes
  the lock inside `Eio.Cancel.protect`, calls `Switch.fail sw (Failure "Simulated error")`, and `Fiber.yield ()`
  to hand control over at exactly the right moment; the expected `traceln` ordering is asserted.
  <https://github.com/ocaml-multicore/eio/blob/main/tests/condition.md>
* **Prevents:** ox's "finalizer that suspends while already cancelled". The actionable form of the rule is *not*
  "never suspend in cleanup" — it is "**if you suspend in cleanup, wrap exactly that suspension in
  Cancel.protect, and write the test that forces the interleaving**".
* **Enforced there:** documentation + one named deterministic test. Nothing mechanical.

### F4. Cancel.protect hides the cancellation from its own caller

> "`protect fn` runs [fn] in a new cancellation context that isn't cancelled when its parent is. … Note that
> `protect` does not check its parent context when it finishes."

* **Source:** `Eio.Cancel.protect` doc — <https://ocaml.github.io/odoc/eio/eio/Eio/Cancel/index.html>
  (official docs); implementation comment at `lib_eio/core/cancel.ml:125-127` explains the design intent:
  > "there is no need to check the new context after [fn] returns; the goal of cancellation is only to finish
  > the thread promptly, not to report the error. We also do not check the parent context, to make sure the
  > caller has a chance to handle the result."

* **Prevents:** a fiber that never notices it was cancelled because everything after the protected block also
  happens not to block. *[inference]* This is the same failure shape as F1 but reached by a different route.
* **Enforced there:** documentation, plus an idiom in Eio's own code for the converse problem — only swallow a
  `Cancelled` when the context is *not* still cancelled, i.e. when the cancellation was self-inflicted:
  ```ocaml
  (* lib_eio/core/fiber.ml:36 *)
  | exception Cancel.Cancelled Exit when not (Cancel.is_on sw.cancel) -> ()
  ```
  and the same guard at `lib_eio/core/fiber.ml:118-122`, with the comment: "If this is in response to us asking
  the fiber to cancel then we can just ignore it. If it's in response to our parent context being cancelled …
  then we'll check that context and raise it at the end anyway."

### F5. Cancelled does not carry the cancellation context, so you cannot ask "is this cancellation mine?"

The type is `exception Cancelled of exn` (`lib_eio/core/exn.ml:15`; `lib_eio/core/eio__core.mli:561`), and the
payload is the *reason*:

> "`Cancelled ex` indicates that the context was cancelled with exception `ex`. It is usually not necessary to
> report a `Cancelled` exception to the user, as the original problem will be handled elsewhere. The nested
> exception is only intended for debug-level logging and should generally be ignored."

* **Source:** <https://ocaml.github.io/odoc/eio/eio/Eio/Cancel/index.html> (official docs).
* **Prevents:** writing a handler that pattern-matches on the payload to decide whether to re-raise. The
  supported way is `Fiber.check ()` / `Cancel.is_on` / a flag of your own.
* **Real-project consequence:** `mirage/capnp-rpc`'s test harness has to carry its own `is_cancelled` flag to
  tell its *simulated* cancellation apart from a real one — see F19.
* **Enforced there:** API design; nothing mechanical.

### F6. A cancellation must not be memoized

`Eio.Lazy.from_fun` takes the cancellation policy as an explicit, typed parameter:

> "`cancel` determines how cancellation is handled while forcing:
> - [`Restart`] : if the forcing fiber is cancelled, the next waiting fiber runs [fn] again.
> - [`Record`] : the failure is recorded and the lazy value will always report cancelled if used.
> - [`Protect`] : the forcing fiber is protected from cancellation while running."

* **Source:** `lib_eio/lazy.mli:6-15` (source code, eio 1.6);
  <https://ocaml.github.io/odoc/eio/eio/Eio/Lazy/index.html>.
* **Source (implementation):** `lib_eio/lazy.ml:22-32` — under `Restart` **and** `Fiber.is_cancelled ()` it resets
  the state to `Waiting force` and re-raises, instead of caching `Failed`:
  ```ocaml
  | Cancel.Cancelled _ when cancel = `Restart && Fiber.is_cancelled () ->
    Atomic.set state (Waiting force);
    Promise.resolve r ();
    Fiber.check ()
  ```
* **Source (real consumer):** `semgrep/semgrep` wraps this in `Lazy_safe.ml` and documents the default choice:
  > "Record is closest to normal Lazy behavior"

  <https://github.com/semgrep/semgrep/blob/develop/libs/commons/Lazy_safe.ml> (source code in a real project).
* **Prevents:** a shared cache that one fiber's cancellation permanently poisons — every later user of the cache
  sees "cancelled" although nobody cancelled *them*. *[inference]* This is a distinct member of ox's
  "lost wake-up / poisoned shared state" family and it is invisible in review.
* **Enforced there:** a typed three-way parameter with a documented default; no check.

### F7. Cancelling fast can throw away a value that was already computed

* **Source (issue + maintainer comment):** issue #805 "Nested Fiber.any race condition", reported by @adamchol.
  talex5:
  > "It's due to `Fiber.any` explicitly checking whether it's been cancelled before returning: … I think it might
  > be reasonable to change that to: … That would prioritise not losing a calculated value, rather than cancelling
  > quickly."

  and later, closing the loop:
  > "Originally, `Fiber.any` didn't have a `combine` argument, so it was always expected that it was OK to throw
  > away either result, and aborting early made sense. But with `combine` that's no longer true."

  <https://github.com/ocaml-multicore/eio/issues/805> (issue + maintainer comments).
* **Fixed in 1.6:** `CHANGES.md` (v1.6): "Prioritize returning `Fiber.any` value over cancelling quickly
  (@adamchol @talex5 #806). This works better with the new `combine` option."
* **Prevents:** *[inference]* an ox `race` that selects the first success could silently discard a successful
  result because a sibling's cancellation reached the shared context first. **This was a real bug in Eio, found by
  a user, and fixed in the very version ox uses** — it is the strongest argument for ox having an equivalent test.
* **Enforced there:** implementation fix; the repro is in the issue body.

### F8. first/any is not mutual exclusion

> "Warning: it is always possible that *both* operations will succeed. This is because there is a period of time
> after the first operation succeeds when it is waiting in the run-queue to resume during which the other
> operation may also succeed."

* **Source:** `Fiber.first` doc, `lib_eio/core/eio__core.mli:236-239`;
  <https://ocaml.github.io/odoc/eio/eio/Eio/Fiber/index.html>. The README's "Racing" section gives the io_uring
  example: "if you ask Eio read from two sockets with `io_uring` then the kernel may have already performed both
  reads by the time it tells Eio about the first one." — <https://github.com/ocaml-multicore/eio/blob/main/README.md>.
* **Prevents:** using a race to guarantee "exactly one side effect happened".
## 1.2 Lifetimes, switches and finalizers

### F9. Do not take a switch if you could create one; do not let a resource outlive its switch

> "A function should not take a switch argument if it could create one internally instead. Taking a switch
> indicates that a function creates resources that outlive the function call, and users seeing a switch argument
> will naturally wonder what these resources may be and what lifetime to give them, which is confusing if this is
> not needed. Creating the switch inside your function ensures that all resources are released promptly."

* **Source:** README, "Best Practices → Switches" —
  <https://github.com/ocaml-multicore/eio/blob/main/README.md> (official project documentation), with a BAD/GOOD
  pair.
* **Source (issue, the canonical mistake written down):** issue #548 "Switches documentation", opened by
  @patricoferris:
  > "I think a lot of people's initial response (like mine) is 'Ahhh! This function needs a switch! Quickly, put
  > one at the top of the function that's calling the function that needs a switch'."

  with the example of returning a file opened inside a `Switch.run`. talex5's reply on the same issue adds a
  subtlety:
  > "A resource attached to a switch will be closed when the switch finishes … However, note that closing a
  > resource might not immediately close e.g. the underlying file-descriptor if it's still being used by another
  > operation (which must be running in some other switch)."

  <https://github.com/ocaml-multicore/eio/issues/548> (issue + maintainer comment).
  The same point is in the API docs for `Resource.close`: "Note: if an operation is currently in progress when
  this is called then it is not necessarily cancelled, and any underlying OS resource (such as a file descriptor)
  might not be closed immediately if other operations are using it. Closing a resource only prevents new
  operations from starting." (`lib_eio/resource.mli:111-114`.)
* **Prevents:** use-after-close and the "half frame / partial write" family — a descriptor torn down underneath a
  fiber that is still writing. *[inference]*
* **Enforced there:** README convention. The API makes one direction impossible (you cannot open a file without a
  switch) but nothing checks the other direction.

### F10. Touching a finished switch is a runtime error — and fork deliberately does not raise

* `Switch.check`: "`check t` checks that [t] is still on. ``raise Cancel.Cancelled` If the switch has been
  cancelled." (`lib_eio/core/eio__core.mli:53-55`).
* `Switch.get_error`: "`get_error t` is like `check t` except that it returns the exception instead of raising
  it. **If [t] is finished, this returns (rather than raising) the `Invalid_argument` exception too.**"
  (`lib_eio/core/eio__core.mli:57-59`). Same for `Cancel.get_error` (`eio__core.mli:586-589`).
* `Fiber.fork`: "**If [sw] is already off then [fn] fails immediately, but the calling thread continues.**"
  (`lib_eio/core/eio__core.mli:265`).
* `Switch.on_release`: "If the switch finishes before [fn] can be registered, **it raises `Invalid_argument` and
  runs [fn] immediately instead**." (`lib_eio/core/eio__core.mli:93-95`).
* **Source (test):** `tests/switch.md` shows both behaviours:
  ```
  # let sw = run Fun.id;;
  # Switch.check sw;;
  Exception: Invalid_argument "Switch finished!".
  ```
  and
  ```
  # run (fun sw -> Switch.fail sw (Failure "Cancel");
  #                Fiber.fork ~sw (fun () -> traceln "Not reached");
  #                traceln "Main continues");;
  +Main continues
  Exception: Failure "Cancel".
  ```
  <https://github.com/ocaml-multicore/eio/blob/main/tests/switch.md> (project test suite).
* **Source (source code):** `lib_eio/core/switch.ml:40-47` — `check_our_domain` and `check` both
  `invalid_arg "Switch finished!"`; `switch.ml:164-177` — the finished-switch path of `on_release_full` wraps
  the user's exception in `Release_error ("Switch finished!", ex)` so the original error is not lost.
* **Prevents:** silently forking work into a dead switch and believing it will run; and mistaking "this scope is
  over" for a cancellation. *[inference]*
* **Enforced there:** docs + expect-tests + a stress test that races registration against completion and catches
  `Invalid_argument "Switch finished!"` (`stress/stress_release.ml`).

### F11. Graceful shutdown is an explicit value, not "the scope ended"

> "Resolving this promise causes [s] to stop accepting new connections. `run_server` will wait for all existing
> connections to finish and then return. This is useful to upgrade a server without clients noticing. **To stop
> immediately, cancelling all connections, just cancel [s]'s fiber instead.**"

* **Source:** `Eio.Net.run_server ?stop` doc, `lib_eio/net.mli:434-437`;
  <https://ocaml.github.io/odoc/eio/eio/Eio/Net/index.html> (official docs).
* **Source (discuss, maintainer):** a user asks how to "wait for all writes to finish and write a Goaway to the
  other side" before a socket is closed; talex5's answer is to nest a second switch so the goodbye happens after
  the inner scope and before the outer scope closes the socket:
  > "If you wanted the client to spawn writers that outlive `run_client`, you could use a second switch for that"

  <https://discuss.ocaml.org/t/eio-attach-a-handler-between-the-fn-finishes-and-forks-are-awaited/16473>
  (discuss thread, maintainer reply). The reporter's own summary of the problem: "It seems like there's no natural
  way to handle it in eio."
* **Prevents:** *[inference]* ox's "keepalive flood dying after 11 minutes" shape — a connection torn down by scope
  exit while a protocol-level finish handshake is still pending, or a shutdown that either hangs forever or drops
  in-flight work. Eio's answer is that "graceful" and "immediate" are two different, explicitly chosen mechanisms.
* **Enforced there:** API shape (a `?stop` promise) + docs. No check.

### F12. Release hooks have exactly four documented properties

> "Release handlers are run in LIFO order, in series.
> Note that [fn] is called within a `Cancel.protect`, since aborting clean-up actions is usually a bad idea and
> the switch may have been cancelled by the time it runs. You cannot attach new resources to a switch once the
> cancel hooks start to run.
> This function is thread-safe (but not signal-safe). If the switch finishes before [fn] can be registered, it
> raises `Invalid_argument` and runs [fn] immediately instead."

* **Source:** `Switch.on_release` doc, `lib_eio/core/eio__core.mli:81-95`;
  <https://ocaml.github.io/odoc/eio/eio/Eio/Switch/index.html> (official docs).
* **Source (source code):** `lib_eio/core/switch.ml:108-109`:
  ```ocaml
  !queue |> List.iter (fun fn -> try Cancel.protect fn with ex -> fail t ex);
  ```
  i.e. a failing release hook does not abort the remaining hooks; it is *added* to the switch's failure set.
* **Source (multi-domain guidance):** `remove_hook` doc — "For multi-domain code, consider using
  `try_remove_hook` instead so that you can handle the case of trying to close a resource just as another domain
  is closing it or finishing the switch." (`lib_eio/core/eio__core.mli:119-124`); `try_remove_hook` "Returns
  `true` if the hook was successfully removed, or `false` if another domain ran it or removed it first."
* **Source (stress test):** `stress/stress_release.ml` — 3 domains × 1000 rounds, each worker registering and
  randomly cancelling release hooks while the main domain finishes the switch; the assertion is
  > "At the end, we check that the number of resources allocated matches the number freed."
  <https://github.com/ocaml-multicore/eio/blob/main/stress/stress_release.ml> (project test suite).
* **Prevents:** attaching a resource during teardown (leak); a release hook raising and masking the real failure;
  double-release across domains.
* **Enforced there:** docs + a counting stress test.

## 1.3 Blocking the scheduler

### F13. Never hold a Stdlib.Mutex across a suspension point

> "Unlike `Stdlib.Mutex`, which blocks the whole domain while waiting to take the mutex, this module allows other
> Eio fibers to run while waiting. You should use this module if your critical section may perform blocking
> operations, while `Stdlib.Mutex` may be more efficient if the lock is held only briefly and the critial section
> does not switch fibers."

* **Source:** `Eio.Mutex` module doc, `lib_eio/eio_mutex.mli:1-11`;
  <https://ocaml.github.io/odoc/eio/eio/Eio/Mutex/index.html> (official docs; the typo "critial" is in the source).
* **Source (README, the permission):** "If the operation being performed is very fast (such as updating some
  in-memory counters), then it is fine to use the standard library's `Mutex` instead." and "If the operation does
  not switch fibers *and* the resource is only accessed from one domain, then no mutex is needed at all."
  <https://github.com/ocaml-multicore/eio/blob/main/README.md>.
* **Source (a real deadlock, in Eio itself):** issue #488, "`Eio.Stream.add` dead locked when stream is empty and
  another domain is blocked taking". talex5's diagnosis:
  > "What's happening here is that `dt` crashes with an unhandled effect exception, leaving the stream mutex
  > locked. Then `da` hangs trying to get the lock."

  and @patricoferris:
  > "The stream implementation uses a Mutex to synchronise access, because of the unhandled effect in `dt` this
  > mutex has not been released and so now `add` is deadlocked"

  <https://github.com/ocaml-multicore/eio/issues/488> (issue + maintainer comments).
* **Source (a real whole-domain block, in Eio itself):** issue #793 "on Windows, reading from stdin blocks the
  whole domain." — <https://github.com/ocaml-multicore/eio/issues/793> (talex5: "Probably needs a check for this.
  I see posix has one, but windows doesn't").
* **How Eio enforces it in its own code** (this is the transferable technique): it uses `Stdlib.Mutex` internally
  **only** in the "release before you suspend" discipline.
  `lib_eio/waiters.ml:41-62` registers the waiter and then `Mutex.unlock mutex` **inside the suspend callback**,
  i.e. the lock is released at the instant the fiber is parked and re-taken after it resumes.
  `lib_eio/stream.ml:17-21` has a `with_mutex` that releases on both the success and the exception path, and
  every blocking path in `Stream.add`/`take` goes through `Waiters.await ~mutex:(Some t.mutex)`.
  `lib_eio/eio_mutex.ml:113-121` (`use_rw`) poisons the mutex on an exception rather than silently leaving it
  held.
  And the POSIX backend refuses to block: `lib_eio_posix/low_level.ml:68` — `if Fd.is_blocking fd then
  await_readable "read" fd;` — it will wait for readiness rather than perform a blocking read on a non-ready fd.
* **Prevents:** ox's "Stdlib mutex held across a suspension (blocks the whole domain)".
* **Enforced there:** documentation + code discipline + a backend guard. **No lint, no ppx, no CI check.**

### F14. The sanctioned escape hatches for blocking work are named, and there are only three

* `Eio_unix.run_in_systhread`: "`run_in_systhread fn` runs the function [fn] using a pool of system threads
  (`Thread.t`). This pool creates a new system thread if all threads are busy, it does not wait. `run_in_systhread`
  allows blocking calls to be made non-blocking." (`lib_eio/unix/eio_unix.mli:72-78`.)
* `Eio.Executor_pool`: "`Eio.Executor_pool` is the recommended way of leveraging OCaml 5's multicore capabilities."
  with `~weight` documented as "the anticipated proportion of a CPU core used by the job" and `~domain_count` with
  "consider reducing this number by 1 if your original domain will be performing CPU intensive work at the same
  time" (`lib_eio/executor_pool.mli:6, 40-53`).
* `Eio.Net.run_server`: "For services that are bottlenecked on CPU rather than IO, you can run a single accept
  loop and have the handler submit CPU-intensive jobs to an `Executor_pool`." (`lib_eio/net.mli:429-430`.)
* `doc/multicore.md`, "Safety Guidelines": "You should assume that values created by an OCaml library are not
  multicore safe, unless specified otherwise." and the four sanctioned ways of sharing mutable values (1. a
  designed-thread-safe value; 2. owning-domain-updates-in-response-to-messages; 3. wrap with a mutex; 4. transfer
  if the sender will never use it again), plus the warning that (2) and (3) are not the same:
  > "if `q` is wrapped by a mutex (as in 3) then the assertion could fail. The first `Queue.length` will lock and
  > then release the queue, then the second will lock and release it again. Another domain could change the value
  > between these two calls."

  <https://github.com/ocaml-multicore/eio/blob/main/doc/multicore.md> (official project documentation).
* **Prevents:** an agent inventing an ad-hoc `Domain.spawn` or `Unix.sleep` inside a fiber because it did not
  know there was a named, supported way.

### F15. Lost wake-ups are a first-class, still-open bug class in Eio — and the report contains the test technique

* **Source (issue, open, filed by @samoht, a Mirage/Tarides maintainer):** #946 "eio_posix: a signal that arrives
  just before poll is handled only at the next timer":
  > "a signal that arrives after the runtime's last check for pending signals and before `poll(2)` starts is
  > recorded but does not wake the scheduler. Its OCaml handler runs only when something else ends the `poll`: the
  > next timer, or never. This is ocaml/ocaml#13189 as eio_posix meets it; #732 is the eio_linux side.
  > It bites hardest on child processes, since eio_posix learns that a child exited only through SIGCHLD: on a
  > loaded machine we see subprocesses that exited at once reported at an unrelated 30 s timeout."

  The report includes a **C shim that makes the race window deterministic** (`late_poll.c` sends SIGUSR1 from a
  `poll` interposer immediately before the first blocking `poll`), and the repro is a two-branch
  `Eio.Fiber.first (await the condition) (sleep 5; print "not handled")`.
  <https://github.com/ocaml-multicore/eio/issues/946> (issue, open at the time of writing).
* **Prevents:** ox's ppoll/SIGCHLD lost wake-up. Note the two transferable techniques, neither of which is a
  library feature: **(a) make the window deterministic with a foreign stub instead of hoping**, and **(b) express
  the expected behaviour as "handled after 0.0s" vs "not handled after 5s"**, i.e. a timeout-shaped assertion.

## 1.4 Concurrency combinators

### F16. both/pair fail-fast: if either raises, the other is cancelled and its result is lost

> "`both f g` runs [f ()] and [g ()] concurrently. They run in a new cancellation sub-context, and if either
> raises an exception, the other is cancelled. `both` waits for both functions to finish even if one raises (it
> will then re-raise the original exception). … If both fibers fail, `Exn.combine` is used to combine the
> exceptions."

`Fiber.pair` is documented in one line: "`pair f g` is like `both`, but returns the two results."
(`lib_eio/core/eio__core.mli:204-220`.)

* **Source:** <https://ocaml.github.io/odoc/eio/eio/Eio/Fiber/index.html> (official docs).
* **Source (test, showing the shapes):** `tests/switch.md` — "`Fiber.both`, first fails immediately and the other
  doesn't start" and the both-fail case producing `Multiple exceptions: - Failure("Failed 1") - Failure("Failed 2")`
  <https://github.com/ocaml-multicore/eio/blob/main/tests/switch.md>.
* **Source (combination rules):** `Exn.combine` — "Combining with a `Cancel.Cancelled` exception does nothing, as
  these don't need to be reported. The result is only `Cancelled` if there is no other exception available."
  (`lib_eio/core/eio__core.mli:512-519`); `Exn.Multiple` — "Raised if multiple fibers fail, to report all the
  exceptions. This usually indicates a bug in the program." (`eio__core.mli:505-510`).
* **What I could not find:** **no** issue, PR or discuss thread specifically about `Fiber.pair` surprising anyone.
  `gh api -X GET search/issues -f q='repo:ocaml-multicore/eio "Fiber.pair"'` returns exactly one hit, #577
  ("Feature request: Stream select"), which is unrelated. Stated as absence, not as "there is no surprise".
* **Enforced there:** docs + expect-tests. The fail-fast semantics are a design decision, not a checked rule.

### F17. Condition.await must be called with the mutex held, in a loop

> "Waiters call `await` in a loop as long as some condition is false. Fibers that modify inputs to the condition
> must call `broadcast` soon afterwards so that waiters can re-check the condition."
> "`await t mutex` … You should lock [mutex] before testing whether the condition is true, and leave it locked
> while calling this function."

* **Source:** `Eio.Condition` module doc and `await` doc, `lib_eio/condition.mli:1-4, 47-53`;
  <https://ocaml.github.io/odoc/eio/eio/Eio/Condition/index.html> (official docs).
* **Source (implementation argument):** `lib_eio/condition.ml:58-73` is a seven-step argument that
  "we can only sleep forever if a broadcast never happens after starting [fn]" — i.e. the lost-wake-up property is
  proved in a comment above the code.
* **Source (helper for the lock-free case):** `Condition.loop_no_mutex`, documented with its own hazard: "since
  there is no lock, `load_config` may see a half-written update if the configuration is changed again before it
  finishes reading it" (`lib_eio/condition.mli:63-80`).
* **Prevents:** the condition-variable flavour of a lost wake-up.
## 1.5 Testing conventions — how the Eio world tests cancellation

This is the part of the mission's brief with the clearest answer, so it gets its own section.

### F18. Deterministic expect-tests over traceln output, run as MDX

> "Within a domain, fibers are scheduled deterministically. … In particular, if you test your code by providing
> (deterministic) mocks then the tests will be deterministic. An easy way to write tests is by having the mocks
> call `traceln` and then comparing the trace output with the expected output. See Eio's own tests for examples,
> e.g., tests/switch.md."

* **Source:** README, "Design Note: Determinism" —
  <https://github.com/ocaml-multicore/eio/blob/main/README.md> (official project documentation).
* **How enforced:** the whole `tests/` directory is an MDX suite — `tests/dune` is literally
  `(mdx (package eio_main) (enabled_if (<> %{os_type} "Win32")) (deps (env_var "EIO_BACKEND") (package eio_main)))` —
  and CI runs `opam install <pkgs> --with-test`, which runs `dune runtest`
  (`.github/workflows/main.yml`). The README is itself an MDX test, with `<!-- $MDX skip -->` and
  `<!-- $MDX non-deterministic=command -->` markers to opt out, so **the default for a documentation example is
  "this runs"**. To keep expected output backend-independent the docs use `Eio.Exn.Backend.show := false`.
* **Prevents:** documentation that drifts from behaviour; and, for ox, non-deterministic tests that an agent
  cannot re-run reliably.

### F19. Injecting cancellation at a chosen suspension point — yes, there is a convention, in three flavours

**Flavour A — a cancel handle returned from a fixture (capnp-rpc, talex5's own project).**

```ocaml
(* mirage/capnp-rpc test/test.ml:74-89 *)
(* Run [fn ~sw] in a daemon fiber with a sub-switch.
   Return a function to cancel the switch and the result of [fn]. *)
let fork_with_cancel ~sw ~tags fn =
  let x, set_x = Promise.create () in
    Fiber.fork_daemon ~sw (fun () ->
        let is_cancelled = ref false in
        try
          Switch.run @@ fun sw ->
          let cancel () = is_cancelled := true; Switch.fail sw Simulated_failure in
          Promise.resolve set_x (cancel, fn ~sw);
          Fiber.await_cancel ()
        with Simulated_failure when !is_cancelled ->
          Logs.info (fun f -> f ~tags "Vat shut down by simulated failure");
          `Stop_daemon
      );
    Promise.await x
```

and a named test in the Alcotest list — `run_eio "Cancel" test_cancel;` (line 786) — whose body uses
`Fiber.first (slow ping; assert false) (fast ping)` to prove the slow operation really was interrupted
(`test/test.ml:221-234`). Source: <https://github.com/mirage/capnp-rpc/blob/master/test/test.ml> (source code in a
real project, by the Eio maintainer).

Note the three techniques packed into fifteen lines: **(i)** the fixture hands the test a `cancel : unit -> unit`
handle rather than the test having to know where to interpose; **(ii)** `Fiber.await_cancel ()` is placed exactly
where the test wants the cancellation to land; **(iii)** because `Cancelled` carries no context (F5), the harness
keeps its own `is_cancelled` flag so the guard `when !is_cancelled` can tell its own simulated cancellation from
a real one.

**Flavour B — an explicit cancellation context handed back by the test scheduler.**

```ocaml
(* lib_eio/tests/dscheck/fake_sched.mli *)
val run : (unit -> unit) -> Eio.Cancel.t option
(** [run fn] runs [fn ()] in a new fiber and returns its context so it can be cancelled.
    Returns None if it never suspended. *)
val cancel : Eio.Cancel.t -> unit
(** [cancel ctx] cancels the context with a suitable dummy exception. *)
```

implementation `lib_eio/tests/dscheck/fake_sched.ml:1`: `let cancel ctx = Eio.Cancel.cancel ctx (Failure "test
cancellation")`. The `None` case is itself an assertion: "the fiber never suspended" is a distinguishable
outcome.

**Flavour C — the manual interleaving in a trace test**, i.e. `tests/condition.md`'s "Cancelling while the mutex
is held" (quoted in F3): `Switch.fail sw (Failure "Simulated error")` + `Fiber.yield ()` +
`Eio.Cancel.protect` to pin the interleaving, with the expected `traceln` order asserted.

### F20. The mock backend turns "everyone is blocked" into an exception — no timeout needed

> "This backend does not support the use of multiple domains or systhreads, but the tradeoff is that it can
> reliably detect deadlock, because if the run queue is empty then it knows that no wake up event can be coming
> from elsewhere."
> "`run fn` runs an event loop and then calls [fn env] within it. ``raise Deadlock_detected` if the run queue
> becomes empty but [fn] hasn't returned."

* **Source:** `lib_eio/mock/backend.mli:1-12` (source code, eio 1.6);
  <https://ocaml.github.io/odoc/eio/eio_mock/Eio_mock/Backend/index.html>.
* **Source (test):** `tests/mocks.md` — "`Eio_mock.Backend.run @@ fun () -> let p, _r = Promise.create () in
  Promise.await p;;`" gives `Exception: Eio_mock__Backend.Deadlock_detected.`
* **Prevents:** *[inference]* ox's lost-wake-up class, mechanically and without a timeout, in the cases where the
  test runs on a single domain with no external events.

### F21. Exhaustive interleaving testing with dscheck, including cancellation

* **Source:** HACKING.md, "Concurrency primitives": "`lib_eio/tests/dscheck` uses [dscheck] to perform exhaustive
  testing of all atomic interleavings." (with the honest caveat "At the time of writing, dscheck has some
  performance problems that make it unusable by default, so you must use the version in
  https://github.com/ocaml-multicore/dscheck/pull/22 instead.")
  <https://github.com/ocaml-multicore/eio/blob/main/HACKING.md> (contributor documentation).
* **The test shape** (`lib_eio/tests/dscheck/test_semaphore.ml`): N `Atomic.spawn` actors, each attempting
  `acquire`; if it cannot proceed it registers a suspendable request; at the end, requests may be cancelled —
  and `Atomic.final` asserts the **invariant**: `assert (Atomic.get t.state = capacity)` plus
  "Do a dummy non-cancelled operation to ensure the pointers end up together". In other words: *a cancelled
  `acquire` must not lose a token.*
  <https://github.com/ocaml-multicore/eio/blob/main/lib_eio/tests/dscheck/test_semaphore.ml> (project test suite).

### F22. Stress and fuzz as separate, cheap gates

* `stress/`: `stress_release.ml` (3 domains × 1000 rounds racing resource registration against switch
  completion, counting allocations vs frees), `stress_semaphore.ml`, `stress_proc.ml`. HACKING.md: "The
  `stress` directory contains stress tests (that try to trigger races by brute force)."
* `fuzz/`: `fuzz_buf_read.ml`, `fuzz_buf_write.ml`, `fuzz_inherit_fds.ml`, run under afl-fuzz with a
  seed corpus; HACKING.md gives the exact `afl-fuzz -m 1000 -i input -o output
  ./_build/default/fuzz/fuzz_buf_read.exe @@ ` command line.

### F23. Some of the scheduler is formally verified

* **Source:** HACKING.md, "Formal verification": "Some parts of Eio have been formally verified:" linking
  <https://github.com/addap/master-thesis/tree/main/documents> and
  <https://github.com/clef-men/zebre/tree/main/theories/eio>. Related: PR #682 "Link to verification work in docs"
  (`label:documentation`). I did not read the proofs themselves — only the claim and the links.

## 1.6 Documentation conventions

### F24. Eio's per-function documentation convention exists and is consistently applied — but I could not find it written down anywhere

The mission asked specifically about "its `.mli` doc-comment convention of stating cancellation and finalizer
behaviour per function". The convention is **real and consistent**. From the 1.6 `.mli`s, the recurring fields are:

| Field | Example (verbatim) | Where |
|---|---|---|
| what it raises, and when | "``raise Cancel.Cancelled` If the switch has been cancelled." | `Switch.check`, `eio__core.mli:55` |
| behaviour if cancelled mid-operation | "It will be unlocked while the fiber is waiting and locked again before returning (it is also locked again if the wait is cancelled)." | `Condition.await`, `condition.mli:52-53` |
| behaviour if aborted | "``raise Flush_aborted` if `abort` is called before the data is written." | `Buf_write.flush`, `buf_write.mli:259-263` |
| who owns/releases what | "You cannot attach new resources to a switch once the cancel hooks start to run." | `Switch.on_release`, `eio__core.mli:91` |
| thread- and signal-safety | "This function is thread-safe (but not signal-safe)." | `Switch.on_release`, `eio__core.mli:93` |
| aliasing/lifetime of a returned view | "Performing any operation that might add to the buffer may invalidate this, so it should be used immediately and then forgotten." | `Buf_read.peek`, `buf_read.mli:287-291` |
| a documented warning where the behaviour is surprising | "Warning: it is always possible that *both* operations will succeed." | `Fiber.first`, `eio__core.mli:236` |
| the parameter's trade-off | "``param protect` If `true`, uses `Cancel.protect` to prevent the critical section from being cancelled. Cancellation is not prevented while waiting to take the lock." | `Mutex.use_rw`, `eio_mutex.mli:29-30` |

**But:** I read `HACKING.md` in full (158 lines: installing, layout, writing a backend, tests, formatting, docs
generation, AI-generated code). **It contains no section on doc-comment style.** I also grepped the repository for
a style guide and found none. So the convention is a *maintainer habit*, not a *written rule* — which means an AI
agent cannot check itself against it. **That is the single biggest gap this research found, and it is exactly the
gap ox's ADR-0010 ("wrong code must fail to compile, or fail the gate") exists to close.**

### F25. The project's AI policy is a direct constraint on ox's method

> "Contributing to Eio should not be done *solely* using "AI tools" such as ChatGPT. … **It is often more work to
> review**. Particularly for the OCaml ecosystem and libraries like Eio, it seems that these tools are not very
> good and generate a lot of believable code that is in actual fact completely wrong. PR comments and the code
> submitted with them can say completely different things."

* **Source:** `HACKING.md`, "AI-generated Code" — <https://github.com/ocaml-multicore/eio/blob/main/HACKING.md>.
* **Relevance to ox (this is a consequence, not a rule to copy):** ox *is* AI-written, so **upstream will not
  accept the fixes ox's research produces, and will not review AI-generated patches.** ox cannot rely on
  "someone upstream will catch it"; every Eio-side hazard ox identifies has to be handled on ox's side of the
  boundary (its own wrapper signatures, its own gates, its own tests). *[inference]*

### F26. What "hardening a user of Eio" looks like when the community writes it down

Two agent-facing artifacts exist, and neither is upstream-official:

* `avsm/ocaml-claude-marketplace`, `plugins/ocaml-dev/skills/eio/SKILL.md` —
  <https://github.com/avsm/ocaml-claude-marketplace/blob/main/plugins/ocaml-dev/skills/eio/SKILL.md> (a community
  skill for coding agents, by an OCaml maintainer). It contains a "Good and Bad Examples" section with exactly
  the shapes this report is about — e.g. "**Bad**: Critical cleanup can be cancelled" / "**Good**: Protect
  critical operations" with `Eio.Cancel.protect @@ fun () -> flush_and_close connection` — and a "Common Gotchas"
  table ("Racing reads | Both reads may complete at kernel level | Don't rely on `Fiber.first` for mutual
  exclusion"; "Condition spurious wakeup | … | Always check condition in `while` loop"; "Missing RNG init |
  Predictable crypto"). A local copy exists on this machine at
  /home/ribelo/.dotfiles/skills/reference/avsm/eio/SKILL.md, which is how I read it.
  I did **not** verify the upstream file byte-for-byte against the local copy.
* The `eio` skill installed in this DSH session
  (/home/ribelo/.dotfiles/skills/engineering/languages/eio/) — a locally-authored, agent-facing checklist. Its
  `references/guidance.md` "Review checklist" is the closest thing to a written rule set I found anywhere:

  > "- Capabilities are explicit. - Switch ownership matches resource and fiber lifetime. - Fiber concurrency is
  > not confused with domain parallelism. - Queues, buffers, reads, and deadlines are bounded by requirements. -
  > Cancellation and sibling failure clean up resources. - Blocking non-Eio work is isolated with the API
  > supported by the installed backend. - Error translation preserves useful context and cancellation. -
  > Version-sensitive integrations are checked against installed package docs."

  and `references/core-concepts.md`: "Never return a resource whose owning switch has already ended." and
  "Keep cancellation protection narrow and bounded so shutdown cannot hang indefinitely. Preserve cancellation
  exceptions unless a boundary intentionally translates them."
  **This is a local artifact, not an upstream source.** I cite it as prior art for the *form* of the answer, not
  as authority.

## 1.7 Absences inside Eio that matter to ox

Stated as absences, with the search that established them.

### F27. Buf_read says nothing about cancellation

I grepped all of `lib_eio/buf_read.mli` **and** `lib_eio/buf_read.ml` (eio 1.6) for `cancel`: **zero hits.**
There is no documented statement about what happens to already-buffered bytes when a read is cancelled part-way
through a parse. This is directly relevant to ox's "half frames in a protocol parser" class, and it means **ox
cannot borrow a rule here — it has to write one.**

What *does* exist and is the natural basis for such a rule:

* `Buf_read.peek` + `Buf_read.consume` form a two-phase commit: "`consume t n` discards the first [n] bytes
  from [t]'s buffer. Use this after `peek` to mark some bytes as consumed. … Note: unlike `skip`, this will not
  read data from the underlying flow." (`buf_read.mli:305-312`). *[inference]* A parser written as
  "peek → decide → consume" is cancellation-safe by construction; one written with `take`/`ensure` is not,
  because those consume as they go. **Eio does not say this anywhere; I am inferring it from the API shapes.**
* The write side *does* have an explicit abort path — `Buf_write.abort`, `exception Flush_aborted`, "If [t] has
  been closed with `abort` then flush operations fail instead of completing successfully"
  (`lib_eio/buf_write.mli:83-84, 293-295`) — and partial writes are handled: "`serialize t writev` calls
  `writev bufs` each time [t] is ready to write. In the event that `writev` indicates a partial write,
  `serialize` will call `Fiber.yield` before continuing." (`buf_write.mli:317-320`). So the asymmetry is real:
  writes have a documented abort and partial-write story, reads do not have a documented cancellation story.

### F28. There is no documented rule about two fibers sharing one buffer

I grepped `lib_eio/*.mli` and `lib_eio/core/*.mli` for "must not be shared", "same buffer", "buffer.*other
fiber", "only.*during the call": **zero hits.** `Eio.Flow.single_read`'s only constraint on the buffer is
"`buf` must not be zero-length" (`lib_eio/flow.mli:33-44`). So ox's "two fibers sharing one mutable I/O buffer"
class has **no upstream rule to borrow**, and ox's own capability/ownership discipline has to supply one.

### F29. cohttp-eio has no cancellation policy at all

I downloaded `mirage/ocaml-cohttp` `master` and grepped the entire `cohttp-eio/` tree (src, examples, tests)
for `cancel`, `protect` and `Mutex`. The only hits are `Eio.Switch.run` in examples and `Switch.t` in type
signatures: `type t = sw:Switch.t -> Uri.t -> connection` (`cohttp-eio/src/client.ml:6`), `type conn =
Eio.Switch.t * Eio.Net.Sockaddr.stream` (`cohttp-eio/src/io.ml:13`). **There is no `Eio.Cancel.Cancelled`
handling, no `Cancel.protect`, no `Eio.Mutex`, and no documented cancellation policy anywhere in the package.**
Source: <https://github.com/mirage/ocaml-cohttp/tree/master/cohttp-eio>. Absence, established by exhaustive grep of
the package.

### F30. Nothing that looks like a lint, ppx or CI gate for Eio users exists

I looked for: a ppx that checks Eio usage; a dune rule; an opam lint; a CI check in a consumer that inspects Eio
call sites; a "eio-best-practices" doc beyond the README. I found none. The relevant opam packages are
`eio`, `eio_main`, `eio_linux`, `eio_posix`, `eio_windows`, `eio-unix`, `eio-ssl`, `eio-trace` and
`eio-friendly` (https://opam.ocaml.org/packages/?q=eio). Of these, `eio-trace` is "Trace visualisation for Eio
programs" by Thomas Leonard, version 0.4, homepage <https://github.com/ocaml-multicore/eio-trace> — a *debugging*
tool, not a checker. **I could not retrieve any information about `eio-friendly` (its opam page returned no
readable content in my fetch), so I make no claim about it — UNVERIFIED.** Eio's own CI
(`.github/workflows/main.yml`) runs `opam install … --with-test` (which runs `dune runtest`, hence MDX) plus
`dune build` and two example binaries; there is no static analysis step.

**The community's answer to "how do I know my Eio code is right" is: deterministic trace tests, a
deadlock-detecting mock, dscheck, stress tests, fuzzing, and reading the docs. Not a checker.**
---

# 2. Things ox should adopt, ranked

Ranked by (damage prevented × ox-specific fit) ÷ cost. "Cost" is engineering cost inside ox, not research cost.

### 1. A mechanical documentation contract for cancellation, ownership and blocking — because Eio's convention is unwritten (F24) and ox's agents cannot be trusted to infer it

**Shape.** Every public value in every ox `.mli` carries four tags, and `scripts/doc-contract-gate` (a small
script, wired into the pre-commit list next to `scripts/caps-gate`) fails the build if a public value is missing
any of them:

```ocaml
val read_frame : Buf_read.t -> (frame, [> `Eof | `Protocol of string ]) result
(** ...
    ``cancellation suspends:yes
    ``cancellation on_cancel: nothing is consumed from the buffer; the caller may retry
    ``finalizer    none (borrows the reader)
    ``blocking     no
    ``lock         none held across the suspension *)
```

The gate checks **presence and vocabulary**, not truth. Truth is the job of items 2 and 3 and the tests. This
mirrors `docs/caps.md` + `scripts/caps-gate` exactly: a capability in the signature, a gate that refuses the raw
ones.

**Cost.** Low: one script, one dune/CI rule, plus a one-off sweep over existing `.mli`s. The risk is tag rot, which
is why the tags should be short and enumerated rather than free prose.

**Why first.** Every other item on this list is a rule an agent must *remember*. This is the only item that makes
the rule *checkable*, and ADR-0010 says that is what ox does.

### 2. A deadlock-detecting test backend (F20)

**Shape.** A test-only scheduler whose `run` asserts: "the run queue is empty and the main function has not
returned ⇒ raise `Deadlock_detected`". In ox terms this is a property of the test harness around `Scope.run`,
not of the production scheduler. A test then reads:

```ocaml
let () = Alcotest.check_raises "no lost wake-up" Deadlock_detected (fun () ->
  Ox_test.Backend.run @@ fun () -> Ox.Promise.await never_resolved)
```

**Cost.** Medium: ox needs a deterministic test scheduler with an inspectable run queue. If ox's tests already
drive one, this is a small delta. If not, this is the largest single item on the list — and probably still worth
it, because it is the only mechanical answer to the lost-wake-up class that needs no timeout and no flakiness.

### 3. "Cleanup may suspend only under Cancel.protect", as a written rule with the test that forces the interleaving (F3)

**Shape.** One paragraph in `docs/why-ox.md` (or the caps doc), stating: *a finalizer or cancellation handler may
perform non-suspending cleanup freely; if it must suspend (typically to re-acquire a lock, or to wait for an
in-flight operation to finish), exactly that suspension is wrapped in `Cancel.protect`, and the function
documents it with ``cancellation on_cancel:`*. Plus one test copied in spirit from `tests/condition.md`'s
"Cancelling while the mutex is held": fork a fiber into a suspending cleanup, fail the scope from the main fiber,
`Fiber.yield ()` to pin the interleaving, and assert the exact trace ordering.

**Cost.** Low — one paragraph and one test — and it converts ox's hardest known bug ("finalizer that suspends
while already cancelled") from a class into a named, testable pattern with a documented exception.

### 4. Make the cancellation policy of every caching/memoizing primitive an explicit typed parameter, defaulting to the safe option (F6)

**Shape.** Wherever ox caches across a suspension, take:

```ocaml
val memo : cancel:[ `Restart | `Record | `Protect ] -> (unit -> 'a) -> 'a t
```

with the doc-comment text lifted in spirit from `Eio.Lazy`: "`Restart`: if the forcing fiber is cancelled, the
next waiting fiber runs the function again. `Record`: the failure is recorded and the value will always report
cancelled if used. `Protect`: the forcing fiber is protected from cancellation while running."

**Cost.** Low (a variant type per primitive). **Why it ranks high:** it is a *compiler-checked* enumeration of
choices — the caller cannot accidentally get the wrong policy, because they must name one — and the failure it
prevents (a cancellation permanently poisoning a shared cache) is invisible in review.

### 5. A Fiber.check-equivalent enforced at ox's Scope.run boundary (F1, F4)

**Shape.** ox already computes a Cause tree at scope boundaries. Add the rule that **a `Cancelled` classified as a
typed failure or a defect must be distinguished from ox's own cancellation**, using Eio's idiom
(`| exception Cancel.Cancelled Exit when not (Cancel.is_on sw.cancel) -> ()`, `lib_eio/core/fiber.ml:36`) as the
model. In ox: `Scope.run` must not report "child failed with Cancelled" when the scope itself was cancelled, and
must report it when a child swallowed a cancellation that was not the scope's.

**Cost.** Low-to-medium. The payoff is that ox's Cause tree stops lying about the most common cause of a
half-finished program.

### 6. Gate the raw blocking calls, don't just document them (F13)

**Shape.** Eio's answer to "don't hold `Stdlib.Mutex` across a suspension" is documentation plus a code
discipline. ox already has the stronger tool: `scripts/caps-gate` "refuses the raw ones". Extend the same idea to
a *blocking gate*: a syntactic check that refuses, in fiber-executed code, `Stdlib.Mutex.lock`,
`Stdlib.Condition.wait`, `Unix.sleep`, and bare blocking `Unix.read`/`write`/`accept`, with an allow-list
comment (the way `nosemgrep` works in `semgrep/semgrep`'s `Lazy_safe.ml`). Where a blocking call is genuinely
required, it must go through the ox-named escape hatch (the `run_in_systhread`/`Executor_pool` analogues), which
is a capability in the signature.

**Cost.** Medium (a syntactic gate is a real program), but it is the only item on this list that turns a
*behavioural* rule into a *compile-time-ish* one, which is precisely what ADR-0010 asks for. Eio itself cannot do
this; ox can.

### 7. Release-hook semantics copied exactly, plus the counting stress test (F12)

**Shape.** ox's scope finalizers must have Eio's four documented properties — LIFO, serial, run under
`Cancel.protect`, and "registering after teardown started is an error but the hook still runs" — written into the
`.mli`, and tested by a stress test in the shape of `stress/stress_release.ml`: N domains × M rounds racing
registration against completion, asserting **allocations = frees**. That single assertion is what catches
double-release and leak-on-race.

**Cost.** Medium. It is the highest-value *runtime* invariant test in Eio's own suite and it is cheap to port.

### 8. Exhaustive-interleaving tests with an invariant asserted at the end (F21)

**Shape.** For each ox synchronization primitive: N actors, each operation either completes or registers a
cancellable request, requests are cancelled, and the final assertion is the invariant — the analogue of
`assert (Atomic.get t.state = capacity)` ("a cancelled `acquire` must not lose a token"). If dscheck itself is
too slow or too version-sensitive to adopt, the same shape runs under a randomized scheduler: weaker coverage,
same invariant, still catches token loss.

**Cost.** Medium-to-high (tooling), high value.

### 9. Make races deterministic with a foreign stub, and assert with a timeout-shaped expectation (F15)

**Shape.** A written rule: *when a race is only reproducible under load, do not add a sleep — add an interposer
that makes the window deterministic, and write the assertion as "handled after 0.0s" vs "not handled after 5s".*
Issue #946's `late_poll.c` + `Fiber.first (await) (sleep 5; "not handled")` is the template, and it is the only
reason that bug is reproducible at all.

**Cost.** Per-race, small; the discipline is the deliverable.

### 10. "Never report a Cancelled" as a rule on ox's error-reporting path (F2, F16)

**Shape.** Eio states this twice: `Net.accept_fork`'s `on_error` — "`on_error` is not called for
`Cancel.Cancelled` exceptions, which do not need to be reported." (`lib_eio/net.mli:402-403`) — and
`Exn.combine` — "Combining with a `Cancel.Cancelled` exception does nothing, as these don't need to be
reported." In ox this is a rule about which Cause nodes may surface to a user-facing reporter, and it deserves a
line in the Cause documentation plus a test that a scope cancelled by a sibling failure reports the *cause*, not
the cancellation.

**Cost.** Low.

### 11. A query on a finished scope returns the error instead of raising (F10)

**Shape.** Eio's `Switch.get_error`/`Cancel.get_error`: "If [t] is finished, this returns (rather than raising)
the `Invalid_argument` exception too." ox's equivalent should do the same, so the error path cannot itself fail.

**Cost.** Trivial. Ranked last only because the damage it prevents is small.

### Cross-cutting: the missing read-side rule (F27)

Item 1's gate will force ox to *write down* what happens to a partially consumed buffer when a read is cancelled,
because the tag ``cancellation on_cancel:` has no default. That is the point: **Eio has no such rule to copy**, so
the gate is what will make ox produce one. My *[inference]* is that the safe shape is "peek → decide → consume"
(`Buf_read`'s two-phase commit) and that any parser built on `take`/`ensure` needs an explicit buffer-state
contract — but that is ox's design decision to make and to test, not something I can cite.

---

# 3. Things that look relevant but do not apply

**3.1 Eio's exception model does not map onto ox's typed failures.** Eio deliberately reports errors with
exceptions and reserves `result` for errors the caller is likely to handle immediately — `doc/rationale.md`,
"Results vs Exceptions": "In anticipation of this, the Eio library prefers to use exceptions in most cases,
reserving the use of `result` for cases where the caller is likely to want to handle the problem immediately
rather than propagate it." (<https://github.com/ocaml-multicore/eio/blob/main/doc/rationale.md>.) ox's rule —
`('a,'err) result` with polymorphic variants, exceptions are defects — is a different, stricter model. **The
*reasoning* transfers** (which errors deserve to be in the type), but the *mechanism* does not, and nothing in
Eio's `Exn`/`Io` machinery should be copied. The one part that does transfer is `Exn.combine`'s heuristic that
cancellation never wins over a real error (F16) — that is a rule about ox's Cause tree, not about exceptions.

**3.2 Eio's Cause-shaped reasoning lives in Exn.combine/Multiple, and ox's Cause tree is strictly richer.**
`Exn.Multiple` is documented as "Raised if multiple fibers fail, to report all the exceptions. This usually
indicates a bug in the program." and `Exn.combine` uses "various heuristics … to simplify the result". ox's Cause
tree (typed failure / defect / interruption with identity / finalizer failure / compositions) already
distinguishes cases Eio flattens. **Do not port Eio's flattening heuristics**; port only the *policy* (cancellation
is not an error; a real error beats a cancellation).

**3.3 Eio's capability/object design and Resource/Pi machinery.** `doc/rationale.md` ("Dynamic Dispatch")
explains that Eio abandoned objects for a value+handler pair with an extensible GADT and a phantom type, and notes
the cost: "care is needed when defining new interfaces, since the compiler can't check that the resource really
implements all the interfaces its phantom type suggests." ox's `Ox_caps.Cap_*` model is the same *idea* with a
different *mechanism*. Nothing to adopt; noting it only because "capabilities" appears in both vocabularies.

**3.4 Fiber.first's "both may succeed" warning is a documentation item for ox, not a mechanism.** ox already says
"race selects the first success" in its own rules. The finding worth keeping is F7 (do not discard a computed
value) — which is a bug ox could have, not a rule ox is missing.

**3.5 The dscheck tool itself.** Eio's HACKING.md is explicit that dscheck was unusable by default at the time of
writing and required a specific PR (<https://github.com/ocaml-multicore/dscheck/pull/22>). Adopting *dscheck* is a
dependency decision with its own risk; adopting the *test shape* (F21) is not. **Recommend the shape, not the
tool** unless the tool is re-evaluated.

**3.6 Eio_mock.Flow/Net mock scripts.** Useful in Eio, but they are Eio-shaped (Eio's `Flow`/`Net`
interfaces). ox's mocks should follow ox's interfaces. The transferable part is the *rule* in the local skill —
"script mock flows for normal data, arbitrary chunking, normal EOF, premature EOF, errors, cancellation, and
writes" — which is a test-coverage checklist, not a mechanism.

**3.7 "Real World OCaml has an Eio chapter".** It does not, as far as I could find. RWO's concurrency chapter is
"Concurrent Programming with Async" (<https://dev.realworldocaml.org/concurrent-programming.html>), and what exists
for Eio is a *community translation* of that chapter
(<https://discuss.ocaml.org/t/i-roughly-translated-real-world-ocamls-async-concurrency-chapter-to-eio/14548>), in
which talex5's replies are the authoritative part — e.g. "You can interrupt any Eio operation by cancelling its
fiber. `Eio.Time.Timeout.run` is an easy way to do that." and "you can use `Fiber.fork_daemon` to run the server
without it preventing the switch from finishing". Cite the thread, not RWO.

**3.8 Eio_runtime_events and eio-trace.** Real, but they are observability tools, not gates. They would help
a human debug an ox program; they would not fail a build. Worth knowing they exist
(<https://github.com/ocaml-multicore/eio-trace>); not part of the hardening answer.

**3.9 eio-friendly.** An opam package with that name exists in the package listing I fetched, but its page
returned no readable content and I found nothing else about it. **UNVERIFIED — I make no claim.**

---

# 4. What I could not find out

Listed explicitly. Absence of evidence, stated as absence.

1. **No written style guide for Eio's .mli doc-comment convention.** The convention is real and consistently
   applied (F24), but HACKING.md has no section on it and I found no style document anywhere in the repository.
   So I cannot tell you *what the maintainers consider a complete doc comment*, only what they in fact write.
   **I did not ask them; there is no question-and-answer channel I used.**

2. **No rationale for several rules, only the rules.** For `Switch.on_release`'s "LIFO order, in series" and for
   `Switch.get_error` returning rather than raising on a finished switch, I found the rule but **not** a statement
   of why. I am not going to invent one.

3. **No issue or discussion about Fiber.pair surprising anyone.** `gh api search/issues` for `"Fiber.pair"` in
   `ocaml-multicore/eio` returns one unrelated hit (#577). This does **not** mean the surprise does not exist; it
   means I did not find it reported.

4. **No published "cancellation injection" convention outside talex5's own projects.** I found the convention in
   `mirage/capnp-rpc`'s `test/test.ml` (F19) and the `fake_sched.ml` mechanism inside Eio's own dscheck tests.
   I did **not** find it written down as a convention anywhere, and I did not find it in `cohttp-eio` (F29) or in
   any other consumer I checked. The convention is real but implicit, like the doc-comment one.

5. **No lint, ppx, dune rule or CI gate for Eio users** (F30). I looked at Eio's own CI, the opam package list for
   anything Eio-adjacent, and `gh search code` for `Cancel.protect`/`Eio.Mutex`/`Fiber.check` across GitHub
   (which surfaced only source files in projects, never a checker). If such an artifact exists, it is not indexed
   where I looked.

6. **Whether Eio 1.6 is the newest release.** I researched against 1.6 because that is what this machine has
   (/nix/store/…-eio-1.6.tbz, and the Eio 1.6 CHANGES.md is the newest section in that tarball). I did **not**
   check the upstream release list for anything newer. Issue #946's report says "(Eio 1.5, OCaml 5.4.1, macOS 27.2
   arm64)", so the reporter was on 1.5, not 1.6. **Whether #946 is fixed in 1.6, I do not know** — the issue was
   open when I read it, and I did not read the eio_posix kqueue code to check.

7. **What semgrep/semgrep was told about Eio.Mutex.use_ro being unsafe.** `Eio_locked.ml` says
   "I (brandon) thought a little bit about whether or not `read` should be allowed to be unprotected, but was told
   this was unsafe, per this discussion: https://github.com/semgrep/semgrep-proprietary/pull/4090#discussion_r2164529565".
   That is a private repository; **I could not read the discussion and therefore cannot tell you what the reason
   was.** The code as written uses `use_ro` for `read` (which is *not* protected) and `use_rw ~protect:true` for
   writes. I am not going to guess which one the comment refers to.

8. **The formal verification results.** HACKING.md asserts "Some parts of Eio have been formally verified" and
   links a master's thesis and a `zebre` development. **I did not read either**, so I cannot say *which* parts, or
   *what* was proved. I report the claim, not the content.

9. **eio-friendly.** See 3.9. No verifiable information retrieved.

10. **The exact current content of the GitHub blob/main URLs I cite.** I verified the quoted text against the
    **eio 1.6 tarball**, not against those URLs. If `main` has moved on since 1.6, the line numbers and possibly
    the wording will differ. The API-doc URLs (ocaml.github.io/odoc/eio/…) I did fetch, and for `Eio.Cancel`
    I confirmed the text matches 1.6 exactly.

---

# Summary

The Eio community hardens these things **almost entirely with documentation and tests, and almost never with a
checker.** The strongest artifacts I found are: a consistently-applied but *unwritten* `.mli` doc-comment
convention that states cancellation, finalizer, locking and aliasing behaviour per function (F24); a mock backend
that converts deadlock into an exception with no timeout (F20); deterministic expect-tests over `traceln` output
run as MDX, including tests that pin a cancellation to an exact suspension point (F18, F19); exhaustive
interleaving tests that assert an invariant after cancellation (F21); a counting stress test for release hooks
(F12); and a bug report (#946) that makes a lost wake-up reproducible by *interposing on poll* rather than by
sleeping (F15). The load-bearing *rules* are: quick cleanup is fine while cancelled but blocking is not (F2); if
cleanup must suspend, only that suspension goes under `Cancel.protect` (F3); a `Cancelled` that you catch and
ignore must be re-checked (F1) and cannot be identified from the exception alone (F5); a cancellation must never be
memoized (F6); cancelling fast must not discard a computed value — a real bug fixed in the version ox uses (F7);
never hold a `Stdlib.Mutex` across a suspension (F13); and touching a finished switch is an error that `fork`
deliberately does not raise (F10).

The gaps that matter most for ox are absences: there is **no written doc-comment style guide** (F24), **no rule at
all about what happens to a buffer when a read is cancelled** (F27), **no rule about sharing a buffer between
fibers** (F28), and **no lint, ppx or CI gate for Eio users anywhere** (F30). ox cannot borrow those; it has to
write them — and because ox has `scripts/caps-gate` and an ADR-0010 mandate, it can do what Eio cannot: make them
*fail the gate* rather than merely be written down. That is the recommendation at the top of section 2.

**Deliverable:** /tmp/eio-hardening/01-eio/REPORT.md
