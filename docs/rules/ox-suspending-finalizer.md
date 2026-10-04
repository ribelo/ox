# ox-suspending-finalizer

Story: ^nlintc-g6k3; evidence: ^nlintc-kdcl.

A `Fun.protect ~finally` must not suspend in a cancelled context. Move a wait
out of cleanup, use `Eio.Switch.on_release`, or shield the **suspension**:

```ocaml
Fun.protect
  ~finally:(fun () -> Eio.Cancel.protect (fun () -> Eio.Promise.await stopped))
  work
```

The typed tier resolves both the cleanup/protection function and known suspending
calls by origin path, so aliases and opens work and same-spelled local modules
are not mistaken for Eio. It tracks nesting: protection of one call does not
protect the next call. Ordinary suspending `Fun.protect` bodies are not finalizers.
`Eio.Cancel.protect` bodies and `Eio.Switch.on_release*` callbacks are traversed
as **already protected** and remain clean. Eio 1.6's own interface documents that
release callbacks run inside `Cancel.protect`; recommending those callbacks
while forbidding their suspension would contradict Eio's answer.

`Fun.protect` wraps a finalizer exception in `Finally_raised`. An unprotected
finalizer interrupted by cancellation therefore does not even propagate as a
plain `Cancelled`, another reason to use protection or a switch release callback.

**Not a liveness proof.** A protected suspension is not safe, only not cancellable:
it can wait forever. Java's `StructuredTaskScope.close` has this hazard; Trio uses
shielded cleanup with a deadline. Bounding protection belongs to row 65's
`?deadline` on `Ox.Cancel.protect`, story ^ncrit-oa64, not this rule.

**Suspending set.** Eio Time sleep/sleep_until (including Mono/Timeout where
available); Fiber yield/await_cancel; Promise await/await_exn; Mutex lock/use_rw/
use_ro; Condition await/await_no_mutex; Semaphore acquire; Stream add/take;
Flow single_read/read_exact/write/copy/copy_string; Buf_write flush; Process
await/await_exn/run; Net accept/connect/send/recv; Eio_unix await_readable/
await_writable/run_in_systhread; Ox Channel send/receive, Select.select,
Fiber.await and Scope.run. Only paths present in the compiler-matched load path
enter the set.

**Accepted false negatives.** This is a finite direct-call analysis, not an effect
system. User wrappers, value aliases, opaque callback values (including record
fields), custom resource implementations, and other suspending APIs are not
inferred. Deferred closures nested in a callback may be conservatively reported.
A closure created under protection but executed later outside it can be missed;
the rule tracks lexical callback bodies, not captured execution contexts.
Stdlib channel close/flush is synchronous (may block a system thread, but does
not yield an Eio fiber). No allow-list entries. The repository's finalizer census
is reported with row 88's verification, not inferred from a lint pass.

## Evidence

[Violating fixture](<../../test/lint/violating/suspending_finalizer.ml>) and
[clean fixture](<../../test/lint/clean/suspending_finalizer.ml>) are compiled/parsed by
[the exact-site tests](<../../test/lint/test_concurrency.ml>). The rule table
registers the replacement, both fixtures and this page for `--self-check`.
Compiler artifacts inherit the engine's strict freshness and CMI checks.
