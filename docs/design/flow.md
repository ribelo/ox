# Flow: a lazy, direct-style stream, after Scala Ox

Status: design only. No code exists and none is written until an application's spec pulls it (ADR-0003); this note is what that spec starts from. It answers ADR-0009's "Flow is the model for streams when an application pulls them" and row 46's stories ^nfloor-pjnk, ^nfloor-idvp, ^nfloor-t8w5 and ^nfloor-tv7b.

Scala Ox's `Flow[T]` is a description of a pipeline that does nothing until it is run, whose stages run in the caller's thread unless a stage introduces an asynchronous boundary, and whose first failure ends the run after every sibling was cancelled and awaited. This library keeps exactly that, with the two-error-kinds doctrine of `docs/why-ox.md` in place of Scala Ox's exceptions-only channel.

## 1. The type, and the error type [^nfloor-t8w5]

```ocaml
type ('a, 'e) t
(* A description of a stream of 'a whose run may fail with the typed error 'e.
   A value of this type does nothing until it is run. *)
```

Decision: **`('a, 'e) t` carries a typed error, and every runner returns it as a `result`.** A stage that can fail typed returns `(_, 'e) result`; the first `Error e` ends the run, every fiber the run started is cancelled and awaited, and the runner returns `Error e`. Exceptions are defects: they propagate out of the runner unchanged after the cancel-and-await, exactly what Ox does, and `Scope.run` classifies them. Nothing is caught to be turned into a typed error, and cancellation of the caller is never an `Error`. This is the law of `Concurrent` (raise exactly what a body raises, return exactly the `Error` a body returns, add nothing, swallow nothing), applied stage by stage.

Errors unify by polymorphic variant like everywhere else: `Flow.map_result f` where `f` returns `[> `Decode of _ ]` joins that case to the flow's `'e`.

Representation (not part of the interface): a push pipeline. A flow is a function from a *sink* — `'a -> (unit, 'e) result`, the downstream stage — to `(unit, 'e) result`. `emit` returning `Error e` stops the upstream loop at once; that is how a downstream failure reaches the source without exceptions and how `take` ends an infinite source (it returns a private stop marker that the runner turns into `Ok`). Ox's `FlowEmit` is the same idea.

## 2. Running: a Flow never starts work until run [^nfloor-idvp]

```ocaml
val run_foreach : sw:Eio.Switch.t -> ('a, 'e) t -> ('a -> (unit, 'e) result) -> (unit, 'e) result
val run_to_list : sw:Eio.Switch.t -> ('a, 'e) t -> ('a list, 'e) result
val run_drain   : sw:Eio.Switch.t -> ('a, 'e) t -> (unit, 'e) result
val run_fold    : sw:Eio.Switch.t -> ('a, 'e) t -> init:'b -> ('b -> 'a -> ('b, 'e) result) -> ('b, 'e) result
val run_last    : sw:Eio.Switch.t -> ('a, 'e) t -> ('a option, 'e) result
val run_to_channel : 'e Scope.t -> ?capacity:int -> ('a, 'e) t -> ('a, 'e) Channel.t
```

A flow does nothing until it is run: building one, composing it, and passing it around emit nothing, open nothing and fork nothing; a flow may be run more than once, and each run starts from the beginning with fresh state (a source that is a live resource — a socket, an `Eio.Stream` — is consumed by whichever run reads it, and is documented as single-run).

`sw` follows `Concurrent`: it is the caller's switch, *only checked* (`Invalid_argument` if finished, the cancellation if cancelled), and the runner owns nothing on it. A stage that needs fibers opens its own `Scope.supervised_error` inside the run, a child of the caller's cancellation context, so no fiber outlives the runner and cancelling the caller cancels the pipeline. `run_to_channel` is the one runner that must outlive its call: it forks the pipeline as a `Scope.fork_error` of the given scope and returns a channel that ends with `Done` when the flow completes and `Error e` when it fails (the scope ends with `e` as well).

Cancellation and finalizers: a run is a suspension point at every emit that blocks, cancellable promptly; on failure, exception or cancellation each forked stage is cancelled and awaited, then `on_complete` hooks and `Eio.Switch.on_release` registrations made by the pipeline run, in reverse order, before the runner returns or raises.

## 3. Which stages fork fibers

The table is the cost model: a stage not listed as forking runs in the fiber that called the runner, one element at a time, with no queue.

| Stage | Forks? | What runs where |
| --- | --- | --- |
| sources: `of_list`, `of_seq`, `iterate`, `repeat`, `using_emit`, `of_channel`, `of_stream`, `of_flow`, `lines_utf8` | no | the caller's fiber; `of_channel`/`of_stream`/`of_flow` suspend on the resource |
| `tick ~clock d v` | no | the caller's fiber sleeps on the clock between emits; a mock clock makes it deterministic |
| `map`, `map_result`, `filter`, `filter_map`, `take`, `take_while`, `drop`, `map_stateful`, `intersperse`, `grouped`, `zip_with_index`, `tap`, `on_complete`, `concat_map`, `scan` | no | the caller's fiber, element by element |
| `throttle` | no | sleeps on the clock (or a `Rate_limiter`) in the caller's fiber |
| `buffer ?capacity` | **yes**: one producer for upstream | upstream runs in a fork feeding a `Channel`; downstream in the caller's fiber |
| `map_par ~concurrency`, `map_par_unordered ~concurrency` | **yes**: upstream feeder, up to `concurrency` workers, and an ordered collector | workers in forks; `map_par` restores input order, `map_par_unordered` emits in completion order |
| `merge` | **yes**: one fork per input beyond the caller's | each side into one `Channel`; ends when both are done or one fails |
| `grouped_within ~clock n d` | **yes**: a timer fork | flushes a group when it has `n` elements or `d` elapsed since its first |
| `zip`, `interleave` | **yes** for the second flow | the right flow runs in a fork; the left in the caller's fiber |
| `concat` (`append`) | no | the second runs after the first completes |
| `run_to_channel` | **yes** | one fork of the given scope |
| `of_flow` with `?read_ahead` | opt-in **yes** | a reader fork filling a bounded buffer |

Every forking stage uses `Scope.supervised_error`: its forks are `fork_error`s, so a typed `Error` in any of them ends the whole run with that error and an exception ends it by being raised; the interruption of the losers is suppressed onto the primary outcome.

## 4. Backpressure

Every asynchronous boundary is a bounded `Channel` (`Ox.Channel`: a closable bounded queue, added in row 46 because `Eio.Stream` has no close and `Select` must report closure as a value). `?capacity` defaults to 16, Ox's default buffer. A full channel suspends the producing fiber, an empty one the consuming fiber: a slow consumer slows the source; nothing grows without bound and nothing is dropped. Lossy behaviour is a different operator (`sliding_buffer`/`dropping_buffer`), deferred until a consumer needs it — Leash's `Chrome.events` (bounded to 32, drop-oldest) is the first candidate. Stages in the caller's fiber have no queue: backpressure is the call stack.

Completion travels the same channel: a finished producer calls `Channel.done_`; a failing one ends the scope, which cancels the consumer, so no error has to be threaded through the queue for the pipeline's own stages. `Channel.error` exists for the boundary (`of_channel`, `run_to_channel`) where the other side is outside the scope.

## 5. Operators

Every operator specified here is built (row 76); section 8's consumers say which ones are exercised first.

Sources
```ocaml
val of_list : 'a list -> ('a, 'e) t                             (* first cut *)
val of_seq  : 'a Seq.t -> ('a, 'e) t                            (* first cut *)
val iterate : 'a -> ('a -> 'a) -> ('a, 'e) t
val repeat  : 'a -> ('a, 'e) t
val tick    : clock:_ Eio.Time.clock -> Duration.t -> 'a -> ('a, 'e) t
val using_emit : (emit:('a -> (unit, 'e) result) -> (unit, 'e) result) -> ('a, 'e) t   (* first cut *)
   (* Ox's usingEmit: the escape hatch for callback APIs; emit is only valid inside the callback and in the calling fiber *)
val of_channel : ('a, 'e) Channel.t -> ('a, 'e) t               (* Done ends; Error e fails the run *)
val of_stream  : ?until:('a -> bool) -> 'a Eio.Stream.t -> ('a, 'e) t   (* first cut; ?until is inclusive: the terminal item is emitted, then the flow ends (Leash's Closed) *)
val of_flow : ?chunk_size:int -> _ Eio.Flow.source -> (string, [> `Read of string ]) t  (* bytes -> chunks; the I/O exception is converted here *)
val lines_utf8 : (string, 'e) t -> (string, 'e) t               (* re-chunks by newline; a final unterminated line is emitted *)
val encode_utf8 / decode_utf8 : ...                             (* text <-> byte chunks across multi-byte boundaries *)
```

Files and JSON (Ox's "files and I/O" and "JSON" pages) are compositions, not sources of their own: a file is `Eio.Path.with_open_in` then `of_flow`; NDJSON is `lines_utf8 |> map_result Ox_json.parse`; writing is `run_foreach` into an `Eio.Buf_write`. A streaming JSON *array* reader is deferred (no consumer).

Transformers (`('a,'e) t -> ('b,'e) t` unless noted)
```ocaml
val map        : ('a -> 'b) -> ('a,'e) t -> ('b,'e) t                        (* first cut *)
val map_result : ('a -> ('b,'e) result) -> ('a,'e) t -> ('b,'e) t            (* first cut: a typed failure ends the run *)
val filter     : ('a -> bool) -> ...                                         (* first cut *)
val filter_map / concat_map / scan / zip_with_index / drop / drop_while
val take       : int -> ...                                                  (* first cut; stops the source without reading past n *)
val take_while : ?inclusive:bool -> ('a -> bool) -> ...                      (* first cut; inclusive = Pie's frame-terminated stop *)
val map_stateful : 's -> ('s -> 'a -> 's * 'b) -> ...
val intersperse : ?start:'a -> ?stop:'a -> sep:'a -> ...
val grouped : int -> ('a,'e) t -> ('a list,'e) t
val grouped_within : clock:_ Eio.Time.clock -> int -> Duration.t -> ...      (* forks *)
val buffer : ?capacity:int -> ...                                            (* forks *)
val throttle : clock:_ Eio.Time.clock -> per:Duration.t -> ...               (* spacing, in the caller's fiber *)
val merge   : ?propagate_done:[`Both | `Left | `Right | `Either] -> ('a,'e) t -> ('a,'e) t -> ('a,'e) t
val zip / interleave / concat
val map_par           : concurrency:int -> ('a -> ('b,'e) result) -> ('a,'e) t -> ('b,'e) t   (* ordered *)
val map_par_unordered : concurrency:int -> ...
val tap         : ('a -> unit) -> ...                                        (* first cut: logging/metrics *)
val on_complete : (unit -> unit) -> ...                                      (* runs once on success, failure, exception or cancellation, protected like Switch.on_release *)
```

`map_par` reuses `Concurrent.for_each`'s rule: at most `concurrency` bodies at once, first `Error` or exception cancels the rest. Total functions (`map`, `filter`, `tap`) may raise; the exception propagates. Stages taking a function run it in place and do not retain it past the run.

## 6. Interop

- **Eio.Flow (bytes).** `of_flow` reads a source in chunks of `chunk_size` (default 4096) until end of input; `run_foreach` or a `to_flow` sink writes chunks to an `Eio.Flow.sink`. Reading and writing errors are converted to `result` at this edge, once (doctrine: libraries convert I/O exceptions at their edge); a cancelled read is a cancellation, not an `Error`.
- **Channels and streams.** `of_channel`, `of_stream`, `run_to_channel` above. A stream consumed by two flows steals from itself; single consumer, as Leash's `Cdp.events` already documents.
- **Seq.** `of_seq` and `run_to_list`. `Seq` remains the right tool for finite pure data (row 27).
- **Select.** A flow that needs to react to a channel *and* a flow uses `Select` on `Channel`s at its boundary; `merge` is the operator form.
- **Reactive streams** (Ox's Publisher bridge): rejected, no consumer and no JVM.

## 7. When Flow, and when Seq and Eio

Row 27 measured Pie's stream use and found that `Seq`, direct result loops and `Eio.Stream` cover it; that verdict stands for straight pipelines. Flow is warranted when a consumer needs **any of**: an asynchronous boundary (`buffer`, `merge`, `map_par`, `grouped_within`) with a *typed* error crossing it, inclusive stops on a live source, or the same pipeline described once and run under different sinks. Below that, a loop is shorter, and the design must not be pulled for style.

## 8. First likely consumers, and what each needs [^nfloor-tv7b]

**Leash, CDP events.** `Cdp.events : notification Eio.Stream.t`, ending with `Closed reason`, consumed by a hand loop in `tabs.ml` (`Eio.Stream.take (Cdp.events cdp)`), beside a second loop over `Chrome.events` (bounded 32, drop-oldest). Needs: `of_stream ~until` (inclusive `Closed`), `filter_map` (decode), `tap` (net-log ring), `merge` of the two event sources with either side's failure ending both, `run_foreach` into the registry.
```ocaml
Flow.merge (Flow.of_stream ~until:is_closed (Cdp.events cdp) |> Flow.filter_map registry_event)
           (Flow.of_stream ~until:is_stopped (Chrome.events chrome) |> Flow.map lifecycle_event)
|> Flow.run_foreach ~sw apply_event
```
Today that is two supervised fibers; Flow wins only when a third source or a throttle appears.

**Leash, `run`/drive JSONL output.** `leash drive --out FILE` streams validated records to a JSONL file as pages complete, keeping five samples in memory (`docs/protocol.md`). Needs: `using_emit` over the page loop (or `of_seq`), `map` to encode, `run_foreach` writing a line to an `Eio.Buf_write`, backpressure from the file, `map_par ~concurrency` if pages are fetched ahead, and `Rate_limiter` on the fetch stage. The count and samples are a `run_fold`.
```ocaml
Flow.using_emit (fun ~emit -> crawl_pages ~emit)
|> Flow.map_result validate |> Flow.tap sample |> Flow.map encode_line
|> Flow.run_fold ~sw ~init:0 (fun n line -> write line; Ok (n + 1))
```

**Pie, audio pipeline.** PulseAudio capture to Codex Realtime: capture chunks, PCM conversion, batching to the realtime frame size, admission against byte budgets, send, and an inclusive stop on the terminal event. Row 27 replaced its stream operators by `Seq`, result loops and a consumer-owned admission queue; a `Channel` now provides that closable, bounded queue without hand-rolled mutex and condition. Needs: `of_channel`, `map`, `grouped_within` (frame size or 100 ms), `tap` (accounting), `take_while ~inclusive:true`, `buffer` between capture and network, typed `Error` from the sender ending capture.
```ocaml
Flow.of_channel capture |> Flow.map to_pcm16 |> Flow.grouped_within ~clock 3200 (Duration.ms 100)
|> Flow.buffer ~capacity:8 |> Flow.map_result send_frame |> Flow.run_drain ~sw
```
Sized honestly: the first two are already served by loops; Pie's pipeline is the likeliest first real pull.

## 9. First cut, and not decided

First cut, when a spec pulls it: `t`, `of_list`, `of_seq`, `using_emit`, `of_stream ?until`, `of_channel`, `map`, `map_result`, `filter`, `filter_map`, `take`, `take_while`, `tap`, `grouped_within`, `buffer`, `merge`, `run_foreach`, `run_fold`, `run_to_list`, `run_drain`. About 600 lines over `Channel`, `Select` and `Scope`; no new dependency.

Not decided: lossy buffers; `run_to_channel`'s exact scope type until `Actor` (row 47) fixes how long-lived scopes are handed around; whether `Flow.t` should be `@ portable` (a flow holds closures; cross-domain flows are out under the single-domain caveat of ADR-0009); a streaming JSON array reader; time-based `debounce`; whether `throttle` takes a `Rate_limiter`; the exact byte-chunk type (`string` versus `Cstruct`).
