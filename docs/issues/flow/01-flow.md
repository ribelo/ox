---
status: ready
package: ox (Flow)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Flow: Scala Ox's streams, built

## Problem Statement

`docs/design/flow.md` specifies `Flow` — a lazy `('a, 'e) t`, run by `run_*`, with sources, transformers, asynchronous boundaries over `Ox.Channel`, a typed error that ends the run and cancels siblings — and nothing of it exists. The floor table lists every Flow item as designed, not built.

## Solution

Build the design as written, every operator in it, in direct style over `Ox.Channel` and `Scope`, with the modes of ADR-0010 on its callbacks.

## User Stories

1. As a service author, I want `Flow.t` and the runners (`run_foreach`, `run_to_list`, `run_drain`, `run_fold`, `run_last`) returning `('a, 'e) result`, so that a stream's typed error comes back as a value. ^nflow-zrep
2. As a service author, I want every source of the design (`of_list`, `of_seq`, `iterate`, `unfold`, `tick`, `using_emit`, `of_channel`, `of_flow` for byte flows, `lines_utf8`, `repeat_eval`, `timeout`, `never`, `empty`, `failed`), so that every Scala Ox source has an equivalent. ^nflow-qdnt
3. As a service author, I want every transformer of the design (`map`, `map_result`, `filter`, `filter_map`, `take`, `take_while`, `drop`, `map_stateful`, `intersperse`, `grouped`, `grouped_within`, `sliding`, `throttle`, `tap`, `on_complete`, `on_error`, `zip`, `interleave`, `concat`, `flatten`), so that pipelines are written once. ^nflow-cktb
4. As a service author, I want the asynchronous boundaries (`buffer`, `merge`, `map_par ~concurrency`, `map_par_unordered`, `also_to`) each forking only inside the run's scope and named in their doc as forking, so that the concurrency cost is legible (^nfloor-idvp). ^nflow-cjl4
5. As a service author, I want the lossy boundaries the design deferred (`sliding_buffer`, `dropping_buffer`), so that drop-oldest and drop-newest are operators, not hand-written loops. ^nflow-jljz
6. As a service author, I want the compositions of flow.md §"Files and JSON" as named helpers (`Flow.Io.lines_of_file`, NDJSON in and out, a streaming JSON array reader), so that the Scala Ox files/JSON/text pages have equivalents. ^nflow-bsi3
7. As a kernel maintainer, I want callbacks moded per ADR-0010 (a stage's function `@ local` where it runs in place, fork bodies `@ once`, and the suspension token of row 71 where it lands), so that Flow is no weaker than the rest of the core. ^nflow-ltwi
8. As a kernel maintainer, I want the design's laws tested — nothing runs before `run_*`, the first error ends the run with every fork cancelled and awaited, backpressure bounds every buffer — as properties in `@stress` and as fixed cases in `dune test`, so that the streaming core has the coverage the concurrency core got in row 60. ^nflow-9wes
9. As a maintainer, I want `docs/design/flow.md` updated to say what was built and every deviation, and the floor table's Flow rows set to `have`, so that the design and the code agree. ^nflow-x6zh

## Out of Scope

Reactive-streams interop (a JVM interface).
