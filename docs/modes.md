# OxCaml mode decisions

This pass uses OxCaml 5.4.0+ox and the pinned Eio interfaces. “Global” means the existing unrestricted callback parameter; it does **not** prove domain portability. The table records every public function with a closure argument in current interfaces (nmodes-d2rn, nmodes-8t8v, nmodes-8y46).

| Public function | Callback decision and reason |
| --- | --- |
| `Eta.Result.Syntax.( let* ), ( let+ )` | **Global**; although applied immediately, OxCaml binding-operator elaboration rejects a mode-qualified closure parameter in existing `let*` syntax. |
| `Eta.Retry.retry, repeat` | **Local**; invoke in the calling fiber. Top-level tail-recursive helpers accept the local callback explicitly rather than capture it in an escaping recursive closure. |
| `Eta.Resource.acquire_release ~acquire` | **Local**; acquisition runs before registering release with Eio. `~release` remains **global**: registered on the switch for later invocation. |
| `Eta.Observability.Logger.span ~f` | **Global**; optional OTLP span IDs bind through `Context.with_fields` into `Eio.Fiber.with_binding`, which requires a global callback (nmodes-8t8v, nmodes-8y46). `~pp_err` remains **global**: passed through formatting and retained by the inner logging callback. |
| `Eta.Observability.Logger.Sink.writer` | **Global**; retains `write_line` in the resulting sink for later log records. |
| `Eta.Timeout.timeout` | **Global**; forwarded to `Eio.Time.with_timeout`, whose signature does not accept `local`. |
| `Eta.Scope.run` | **Global**; forwarded to `Eio.Switch.run`, whose signature does not accept `local`. |
| `Eta.Observability.Context.with_fields` | **Global**; forwarded to `Eio.Fiber.with_binding`, whose signature does not accept `local`. |
| `Eta.Concurrent.race, par, all, with_background` | **Global**; tasks fork into Eio fibers, outliving the invocation of the spawning function. |
| `Eta.Schedule.recur_until, modify_delay, while_output` | **Global**; predicates and delay transformation are stored inside the schedule for future steps. |
| `Eta.Cause.pp, pp_compact; Eta.Exit.pp` | **Global**; printers flow through `Format` and recursively applied formatting callbacks; no locally-mode-qualified formatter contract. |
| `Eta_json.array_map` | **Global**; passed to `Stdlib.List.map` (whose callback requires global). Replacing it with a naive recursive map would change stack behavior for large arrays. |
| `Eta_app.status_query` | **Global**; returns a closure retaining the status callback list. |
| `Eta_app.run_for_test, run` | **Global**; test hooks, `?commands` and `?config_commands`, printers, `getenv`, read/write callbacks, `?validate`, `?telemetry` and program may be retained by Cmdliner/Eio switch and by nested callbacks; the `span_ids` the telemetry hook returns is stored by `Logger.create` for later `Logger.span` calls, so rule 2 makes it global too. The validator runs in place, but a trial `@ local` failed at `eta_app.ml`'s `Term.const (execute false)`: "This value is local but is expected to be global" — the Cmdliner term that evaluates `run` and `config check` captures it, so it cannot be `local`. |
| `Eta_app.Config.path, resolve, decode, load` | **Global**; `getenv` and `read` are forwarded to helpers / used by the config load path without a fully local transitive contract. |
| `Eta_test.run, fork_run, with_census` | **Global**; Eio runtime, switch/fork and fiber-local census APIs respectively receive callbacks with no local parameter. |
| `Supervised.start ~spawn` | **Global**; stored for supervised respawns in Eio fibers. |
| `Correlator.create ~read/~write/~id/~set_id/~session` | **Global**; stored in correlator state. Reader runs in another Eio fiber; writer and matchers are invoked for future requests. |
| `Listener.run ~decode/~encode/~handler` | **Global**; forwarded to accepting fibers; handler can outlive the call that spawned it. |

## Portable functions and values (nmodes-6pqn)

The interfaces of `Duration`, `Schedule`, `Cause`, `Exit`, `Interrupt_id`, `Eta_json`, and `Status` begin with compiler-checked `@@ portable`, making their unexcepted functions portable to call from another domain. This is a property of a **function closure**, not an automatic guarantee for all values returned by it. `Duration.t` is `value mod portable contended`; `Interrupt_id.t`, `Status.state`, `Status.t` and `Eta_json.t` have compiler-checked portable value kinds. The rows and portability claims of the schema combinator library, removed in row 16 (`^nnoschema-ttb5`), went with it: a derived codec is plain OCaml, and `docs/adr/0008-types-are-the-schema.md` records why. `Eta_json.parse`, `to_string`, and `compact` have explicit `@@ nonportable` exceptions because they close over nonportable pinned `Yojson.Safe` functions; JSON constructors/accessors remain portable.

`Schedule.t` is **not** portable as an arbitrary value: `Recur_until`, `Modify_delay`, and `While_output` hold unrestricted user callbacks. Requiring portable callbacks would reject currently valid single-domain closures over mutable state. The same held for the removed schema library's values, which retained unrestricted callbacks. `Cause.t` is not universally portable because `Fail` stores arbitrary `'e`, and `Die` stores an exception/backtrace; `Exit.t` includes the arbitrary success payload and `Cause.t`. Portable `string Cause.t` is accepted at an explicit portable parameter in the compile test. No representation or callback contract was changed to overpromise portability: portable schedules would be a separate consumer-driven `eta_par` decision.

`test/modes/portability.ml` sends a `Schedule.t` and `Cause.t` via `Eio.Domain_manager.run` and explicitly checks the concrete Cause argument's portable mode. This exercises transfer and demonstrates the limit: the pinned domain manager accepts an unrestricted closure, so this test **does not prove** an arbitrary schedule is portable. It would be incorrect to claim the Eio call itself supplies that proof.

## Single-domain boundaries (nmodes-yp1i)

Create `Logger`, `Context`, `Correlator`, `Supervised`, `Listener` and `Child` instances per domain. Their Eio handles, fiber-local bindings, mutable counters or unsynchronized lifecycle are not portable state. A future parallel package must own separate instances inside each worker domain rather than share these values across domains. Portable pure functions do not make an enclosing mutable handle portable. `Child.stop` and `Correlator.close` might eventually warrant `unique`/`once` contracts; this pass makes neither promise.

## Allocation evidence (nmodes-78o3)

`Duration.ms`, `to_ms`, `is_zero`, `subtract`, `min`, `max`, `between`, `compare`, and `equal` pass the native compiler's `[@@zero_alloc]` checker. Checked arithmetic that can raise, floating-point conversion, formatting and `Duration.divide` do not receive unsupported assertions. A compiler trial of `Schedule.step [@@zero_alloc]` **failed**: `step_phase` may allocate, and the function allocates a 24-byte replacement driver and a 24-byte result pair. Thus adding the requested assertion without a behavior/API rewrite would be a false guarantee. It was reverted. `bench/correlator_alloc.ml` runs 10,000 complete request/reply calls on Eio's posix backend; one measured run reported 291.00 minor words/call, 0.03 major words/call, 291.03 total allocated words/call from `Gc.quick_stat` deltas after a warm-up and full major collection. Numbers depend on compiler, backend and GC settings; benchmark prints the measured count rather than checking a brittle threshold.

## Pinned upstream gaps (nmodes-cikk)

In pinned `eio/core/eio__core.mli`, `Switch.run : ?name:string -> (t -> 'a) -> 'a` and `Fiber.with_binding : 'a key -> 'a -> (unit -> 'b) -> 'b` take unmoded closures. In `eio/time.mli`, `Time.with_timeout : _ clock -> float -> (unit -> ('a, 'e) result) -> ...` also takes an unmoded closure. Trials making `Scope.run`, `Context.with_fields`, or `Timeout.timeout` local failed against those pinned signatures. `Eio.Fiber.fork`, `pair`, and `first` take unmoded/global task callbacks by design (they are scheduled asynchronously). In `eio/domain_manager.mli`, `Domain_manager.run : _ t -> (unit -> 'a) -> 'a` explicitly warns that thread safety is **not enforced by the type**; it does not demand a portable closure. `Stdlib.List.map` similarly prevents passing a local callback in `Eta_json.array_map` without substituting an algorithm. These are version-specific type gaps, not evidence of a safe cross-domain callback.

The ppx pipeline is a tooling gap of the same kind (nppx-d10y). No ppxlib installs on 5.4.0+ox, so dune `(pps ...)` has no driver to run: `ppx-yojson-minimal` preprocesses text through `(preprocess (action ...))` instead. Two consequences follow. First, merlin and ocamllsp do not run the preprocessor, so a derived `t_of_yojson` reads as unbound in the editor while the dune build (which does run it) is green; the build is the source of truth until a real ppxlib exists. Second, the emitted converters are plain OCaml with no mode annotations; a file that derives over a `local` closure or ships values across domains gets no help from the deriver, and a future signature that needs either states it by hand.

## Rules for future signatures (nmodes-o66p)

1. A callback run in place, in the current fiber, and not retained is `@ local`; test it against every callee.
2. A callback forwarded to Eio or stored for later is global, and the interface says why. Global does not imply portable.
3. Pure modules expose portable functions and portable **value kinds only when their contents permit it**. Stored arbitrary callbacks and payloads prevent unconditional portable values; test the mode with the compiler rather than claiming it by analogy.
