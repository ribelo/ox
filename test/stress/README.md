# Seeded stress (^nstress-xn75, ^nstress-gylw)

These executables have no `runtest` rules. The opt-in `@stress` alias
bounds each suite with an independent OS `timeout 60`, including a stalled
scheduler. Every executable prints its seed and accepts `--seed N`;
`OX_STRESS_SEED` takes precedence. Dune tracks that environment variable.
Use `--force` to repeat a previously successful campaign.

```sh
# Fixed alias seeds (repeat twice):
timeout 900 nix develop -c env -u OX_STRESS_SEED DUNE_BUILD_DIR=_build_r60_stress EIO_BACKEND=posix bash -c 'ulimit -v 16777216; exec dune build @stress --force'
# Exploration, then replay the printed seed:
timeout 900 nix develop -c env OX_STRESS_SEED=937261 DUNE_BUILD_DIR=_build_r60_stress EIO_BACKEND=posix bash -c 'ulimit -v 16777216; exec dune build @stress --force'
```

| Suite | Fixed seed | Checks |
| --- | ---: | --- |
| [core_properties](core_properties.ml) (^nstress-mvpj) | 6075 | 8,000 generated cases plus every-position/timing matrices; ordered fail-fast results, first-success race, ordered all-error causes, bounded admission, caller cancellation during suspended release, every started fiber awaited before the caller switch closes. |
| [parser_fuzz](parser_fuzz.ml) (^nstress-ln4z) | 6060 | Mutated valid inputs and arbitrary bytes, every-byte truncations of [corpus](corpus/), h1 response spans, request parsing through the loopback server, advertised-length bounds, ws roundtrips/masking, H1 writer agreement. |
| [ws_storm](ws_storm.ml) (^nstress-0uv9) | 60057 | 30 seconds of real loopback flood/duplex/half-close rounds, row-57 quiet keepalive/refill/limit checks, joined endpoints and descriptor census. |
| [actor_storm](actor_storm.ml) (^nstress-ttto) | 6060 | Thousands of asks and Channel send/receive operations at several capacities; caller cancellation, timeout, queued cancellation, stop, exactly-once state/message accounting, drained queues and fiber census. |
| [ipc_storm](ipc_storm.ml) (^nstress-kcr6) | 60036 | Eight rounds of 200 concurrent clients, partial requests, disconnects, complete replies including handler-budget replies, every connection accounted for, joined handlers and descriptor census. |

Crowbar is not installed in the existing switch. Per the no-new-dependency
ruling, parser fuzzing uses the installed `qcheck-core` generators and
integrated shrinking plus deterministic corpus/truncation loops. No AFL
campaign or dependency installation is needed. The request parser is private:
its public rejection boundary is the server's 4xx response, not a new parser API.

## v1 inventory (^nstress-gylw)

`git ls-tree -r v1 -- test/stress` is empty: that literal directory does not
exist in the tag. The actual v1 core stress registry is
`v1:test/core_common/stress_common_suites.ml`, with the following 14 cases.
The effect runtime is reference material only; no runtime code was copied.

| v1 case | Ruling | Replacement / reason |
| --- | --- | --- |
| pool no resource leak | not applicable | v1's effect-runtime Pool is absent; the direct-style core uses Eio primitives. The SQL connection pool is a separate package/consumer. |
| semaphore permit accounting | not applicable | The custom runtime Semaphore is absent; Eio owns permit accounting. |
| channel no lost messages | superseded | [actor_storm](actor_storm.ml) validates accepted sends against exactly-once delivered messages while cancelling both sides. |
| retry resource accumulation systematic | superseded | Explicit attempt switches replace effect-runtime accumulation; [v1_completion](../core/v1_completion.ml)'s `retry_resource_cases` checks per-attempt release in the default run. |
| nested scope catch retry releases all | superseded | Default [v1_completion](../core/v1_completion.ml) `retry_race_stress` / `stress_compositions` plus generated boundary/census checks in [core_properties](core_properties.ml). |
| race+retry resources released on scope exit | superseded | Default [v1_completion](../core/v1_completion.ml) `retry_race_stress` already checks this composition with explicit switches; generated race loser census adds timing/cancellation coverage. |
| all_settled scoped resources released | not applicable | The custom `all_settled` API is absent; result collection is explicit in direct style. Generated all/Scope protected-release census preserves the resource-ownership assertion. |
| race many branches resource cleanup | ported | [core_properties](core_properties.ml)'s variable-width race with suspended release and loser census. |
| randomized eff compositions release | superseded | No `Eff`/Runtime/interpreter exists; generated direct-style Scope and Concurrent outcome patterns replace it. |
| randomized race compositions release | ported | Generated mixed-outcome/timing races, first-success law and all-started-await census. |
| randomized all compositions release | ported | Generated mixed-outcome/timing all and bounded for_each, ordered values and await census. |
| all without scoped releases at scope exit | superseded | Switch ownership is explicit; default `stress_compositions` and generated Scope census assert matching acquisitions/releases. |
| par scoped resource released on failure | ported | Generated par positional/timing matrix, fail-fast law and suspended-release census. |
| map_par cancelled workers release | ported | Its direct-style replacement is `for_each`; generated caller cancellation and bounded admission await all started workers. |

The transport fuzz registry is `v1:test/http_fuzz/dune`:

| v1 suite | Ruling | Replacement / reason |
| --- | --- | --- |
| fuzz_h1_parse | ported | [parser_fuzz](parser_fuzz.ml): response parser fuzzing plus request ingress, full corpus truncations, huge lengths and bounds. |
| fuzz_ws_codec | ported | [parser_fuzz](parser_fuzz.ml): mutated frames, both masking modes, encode/decode agreement and oversized 16/64-bit lengths. |
| fuzz_h1_write | ported | [parser_fuzz](parser_fuzz.ml): bytes/buffer/string writer agreement; the removed effectful flow writer is not copied. |
| fuzz_h2_security | not applicable | Ox exposes no HTTP/2 parser, HPACK decoder or flow-control state machine. |

The existing [posix wake-up stress](../stress-posix-wakeup/README.md)
(^nwake-fz0j) stays separate. Its 50-process enabled/disabled comparison can
require 250 seconds per population, exceeding this alias's per-suite budget;
the disabled baseline is diagnostic evidence, not a correctness assertion.
It has no generated/random input, so seed plumbing would not add coverage.
Neither it nor these new suites enters the default run.
