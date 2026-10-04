# 03-simulation — Deterministic, seeded simulation as the default way to test concurrency and protocol code in OCaml

Slot: 03-simulation. Subject: how to make deterministic, seeded simulation the default way concurrency and protocol code is tested, specifically in OCaml. Repositories changed: none. Everything here was read, not written. Crawled sources are cached under /tmp/eio-hardening/03-simulation/sources/ and downloaded source trees under /tmp/eio-hardening/03-simulation/src/.

How to read this:

- "Source says" is a direct quote from the cited artifact; short quotes are given verbatim. "Inference" is mine. Where a project has a rule but no published rationale, I say so.
- Source tiers used: official docs, project READMEs, maintainer blogs, a peer-reviewed paper (FDB, SIGMOD 2021), a conference talk with retrieved transcript, source code in real projects, package documentation and changelogs. Antithesis material is vendor material and is marked as such.
- Version facts verified locally: Eio 1.6 (installed and from the v1.6 source tarball), qcheck-core 0.91, alcotest 1.9.0+ox, OCaml 5.4.0+ox. dscheck and qcheck-stm are NOT installed in this switch; they were read from the network, and I say so where it matters.
- All URLs were fetched on 2026-10-04.

---

## 1. Findings that apply to ox

### 1.0 The fork in the road: pluggable nondeterminism vs a deterministic hypervisor

Antithesis names the two implementation shapes (vendor docs, "Deterministic simulation testing - how it works and when to use it", https://antithesis.com/docs/resources/deterministic_simulation_testing/):

- Shape A, "popularized by FoundationDB ... is to design the system under test so that all nondeterministic components are pluggable." The same page says of it: "Since this requires the system and all its dependencies to be built with deterministic simulation testing in mind, this approach is generally impractical for systems already in production."
- Shape B: "run regular non-deterministic software inside a deterministic hypervisor."

ox is a library kernel, not a deployed system, and it already passes its foreign boundaries explicitly (Eio values plus the Cap_* rows in lib/caps). It can only take Shape A. That decision is what the rest of this section is for.

### 1.1 FoundationDB: the reference implementation

F1. A single process, single thread, deterministic discrete-event simulation of the whole cluster.

Source: official docs, "Simulation and Testing", https://apple.github.io/foundationdb/testing.html. The same text appears in the project's own Joshua README, https://github.com/apple/foundationdb/blob/main/contrib/Joshua/README.md, and is summarized in the SIGMOD 2021 paper, https://www.foundationdb.org/files/fdb-paper.pdf, section 4.

Source says: "Simulation is able to conduct a deterministic simulation of an entire FoundationDB cluster within a single-threaded process." and "Determinism is crucial in that it allows perfect repeatability of a simulated run, facilitating controlled experiments to home in on issues."

What it prevents: bugs whose trigger is a particular interleaving of failures across many processes, which no single-machine example test can reproduce.

How it is enforced: architecturally. The paper (section 4) says: "All database code is deterministic; accordingly multithreaded concurrency is avoided (instead, one database node is deployed per core)." and "all sources of nondeterminism and communication are abstracted, including network, disk, time, and pseudo random number generator." The production implementation is "a simple shim to the relevant system calls."

Inference for ox: the FDB rule is not "add a simulator"; it is "make every nondeterministic thing a dependency you can replace, then forbid the library from reaching around it." ox already has most of that shape (Eio capabilities plus Cap_*), which is why this section applies at all.

F2. Fault injection at two levels: environment faults plus in-code "buggification".

Source: paper section 4 (same URL as F1).

Source says: "The FDB simulator injects machine, rack, and data-center level fail-stop failures and reboots, a variety of network faults, partitions, and latency problems, disk behavior (e.g. the corruption of unsynchronized writes when machines reboot), and randomizes event times." and, for the second level: "At many places in its code-base, the simulation is given the opportunity to inject some unusual (but not contract-breaking) behavior such as unnecessarily returning an error from an operation that usually succeeds, injecting a delay in an operation that is usually fast, choosing an unusual value for a tuning parameter, etc."

The mechanism is code (source: flow/include/flow/Buggify.h, https://raw.githubusercontent.com/apple/foundationdb/main/flow/include/flow/Buggify.h). Verbatim from that file:

    inline double P_GENERAL_BUGGIFIED_SECTION_ACTIVATED{ 0.25 };
    inline double P_GENERAL_BUGGIFIED_SECTION_FIRES{ 0.25 };
    inline double P_EXPENSIVE_VALIDATION{ 0.05 };
    ...
    const double rand = deterministicRandom()->random01();
    const bool activated = rand < P_GENERAL_BUGGIFIED_SECTION_ACTIVATED;
    ...
    return isGeneralBuggifyEnabled() && getGeneralSBVar(location.file_name(), location.line())
           && deterministicRandom()->random01() < probability;

So a buggify site is decided once per file:line per simulation run (25% of runs activate it) and then fires on 25% of the calls within an activated run; the decision is written into the trace by g_traceBatch.addBuggify(activated, line, file). EXPENSIVE_VALIDATION fires on 5% of calls within an enabled run.

What it prevents: rare-state blindness — code paths ordinary inputs never reach (a retry that succeeds on the first try, a tuning parameter that is never odd, an error that never happens locally).

How it is enforced: a macro at the fault site plus the deterministic PRNG; there is no lint. The paper states the tuning constraint: "Fault injection distributions are carefully tuned to avoid driving the system into a small state-space caused by an excessive fault rate."

F3. Swarm testing and conditional coverage.

Source: paper section 4.

Source says: "Swarm testing [40] is extensively used to maximize the diversity of simulation runs. Each run uses a random cluster size and configuration, random workloads, random fault injection parameters, random tuning parameters, and enables and disables a different random subset of buggification points." and, for coverage: "a developer concerned that a new piece of code may rarely be invoked with a full buffer can add the line TEST( buffer.is_full() ); and analysis of simulation results will tell them how many distinct simulation runs achieved that condition. If the number is too low, or zero, they can add buggification, workload, or fault injection functionality to ensure that scenario is adequately tested."

What it prevents: false confidence from a simulator that always injects the same faults; and the "no run ever reached this state" failure mode, which is the same hazard as the excessive-fault-rate one from the other side.

Inference: this is the cheapest high-value idea in this document for ox — a per-run fault mask plus a counter of which fault classes fired, so a run can be failed when a class never fired.

F4. The seed is an input, and determinism itself is tested.

Sources:
- Official docs (F1) on the unit-test seed: "UNIT_TEST_SEED is a decimal seed shared by these entries... It defaults to 1; set it to 0 to choose a random seed, which each runner prints."
- Project wiki, "Debugging in FDB", https://github.com/apple/foundationdb/wiki/Debugging-in-FDB: "Simulation tests are only reproducible on the same OS type, and with the same build environment. A binary from a CMake build in docker may not execute the same as a CMake build in the centos7 VM. Libstdc++ vs libc++ makes determinism change." and "Make sure your test is deterministic by checking the unseed numbers are same across multiple runnings. (The seed initializes the random number generator for the test, and then the unseed is the last random number generated.)"
- Talk: Will Wilson (FoundationDB), "Testing Distributed Systems w/ Deterministic Simulation", Strange Loop 2014, https://www.youtube.com/watch?v=4fFDFbi3toc (transcript retrieved by crawl). The talk says that for about "1% we actually run them twice and then we check ... the exact same things happen in the exact same sequence and at the very end we check those random number generators I mentioned and see what the next random number it would have been generated would have been and if those don't match exactly we know there was a determinism failure and we go track that down".

What it prevents: silent determinism loss. FDB's reproducibility is explicitly qualified by toolchain and OS, and the "unseed" is a cheap end-of-run fingerprint that detects the loss without waiting for a flaky failure.

How it is enforced: a scheduled double-run plus comparison; and the failure report carries the seed, with reproduction as a command, e.g. the wiki's "valgrind --log-file=valg.log ./bin/fdbserver -r simulation -s 366751840 -f ../tests/fast/SwizzledRollbackSideband.toml".

F5. When the simulator cannot reproduce a production bug, extend the simulator before debugging the bug.

Source: paper section 6.2.

Source says: "in the rare circumstances when a bug was first found 'in the wild', the debugging process was almost always first to improve the capabilities or the fidelity of the simulation until the issue could be reproduced there, and only then to begin the normal debugging process." Also: "Adding additional logging, for instance, generally does not affect the deterministic ordering of events, so an exact reproduction is guaranteed."

What it prevents: the production-only debugging trap. It is also the rationale for F2's buggification points existing at all.

F6. Volume and time acceleration.

Source: official docs (F1): "Simulation runs tens of thousands of simulations every night, each one simulating large numbers of component failures... we estimate that we have run the equivalent of roughly one trillion CPU-hours of simulation on FoundationDB." and "The simulation steps through time, synchronized across the system, representing a larger amount of real time in a smaller amount of simulated time. In practice, our simulations usually have about a 10-1 factor of real-to-simulated time, which is advantageous for the efficiency of testing." The talk gives the per-night figure directly: "we can run 5 to 10 million simulation runs per night on our cluster".

Caveat recorded deliberately: the sentence about a "10-1 factor of real-to-simulated time" is ambiguous about direction, and I could not resolve it from the source; the preceding sentence implies fast-forward (a smaller amount of real time covers more simulated time). I do not fill this in.

F7. What simulation caught, and what it cannot catch.

Source: paper sections 4 and 6.2.

Source says: "The harsh simulated environment quickly provokes bugs (including but not limited to distributed systems bugs) in the database, and determinism guarantees that every bug found this way can be reproduced, diagnosed, and fixed." For a concrete latent-bug episode: "after we separated the DataDistributor role from the Sequencer, we were surprised to discover several unknown bugs in the DataDistributor. This is because before the change, DataDistributor is restarted with Sequencer, which effectively reinitializes and heals the states of the DataDistributor." Note what that episode really says: restarts had been healing the bug, and simulation surfaced it only once the healing stopped. On reliability outcomes: "In the past several years, CloudKit has deployed FDB for more than 0.5M disk years without a single data corruption event."

Limits, stated by the paper: "Simulation is not able to reliably detect performance issues, such as an imperfect load balancing algorithm. It is also unable to test third-party libraries or dependencies, or even first-party code not implemented in Flow." And on Jepsen-style external testing: "All of these approaches lack deterministic reproducibility."

### 1.2 TigerBeetle's VOPR: the closest thing to a maintained, documented DST for one codebase

Sources: project docs https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/internals/vopr.md; maintainer blog https://tigerbeetle.com/blog/2023-07-06-simulation-testing-for-liveness/; maintainer blog https://tigerbeetle.com/blog/2025-06-06-fuzzer-blind-spots-meet-jepsen/.

T1. Seed plus commit is the replay key. Source says (vopr.md): "Because our simulator is deterministic based on a seed number and the Git commit, we can perfectly reproduce any bugs discovered in testing for easy local debugging." and "When a simulation causes any type of failure, the seed and Git commit hash can be used to replay back the exact simulation and bug."

T2. Time acceleration is the point. Source says (vopr.md): "Crucially, VOPR can speed up time arbitrarily. One minute of VOPR time is equivalent to days of real-world testing." and "In the simulator, all non-deterministic parts of the system are stubbed out. This includes the clock, network, and disk operations."

T3. Fault injection is a per-tick dice roll. Source says (liveness blog): "on every tick it rolled a dice and, with some probability, crashed a healthy replica, restarted a downed replica, dropped a packet from the network, or corrupted read or write disk I/O."

T4. Assertions are the oracle, and they stay on in production. Source says (vopr.md): "Simulation testing pairs particularly well with TigerBeetle's heavy use of assertions. Throughout the code base there are thousands of assertions checking that all manner of invariants hold true. TigerBeetle is somewhat unique in that it keeps these assertions on, even in production." Simulator-side checkers are separate: "the simulator also includes a variety of additional checkers that verify the correctness of the cluster's state. For example, TigerBeetle replicas' data files are designed to be byte-for-byte identical across caught-up nodes in the cluster. Some of the storage checkers verify that this is the case across simulations."

T5. Two modes, because uniform random fault injection cannot test liveness. Source says (liveness blog): safety mode injects faults uniformly; then "after a time of fault injection, we switch to liveness mode by: picking a quorum of replicas to be fully available (the core), restarting any core replicas which are down at that moment, healing all network partitions between core replicas, and, for all failures involving non-core replicas, making those failures permanent."

What it caught that ordinary tests did not — the repair/round-robin resonance bug. Source says (same post): "the VOPR was able to maneuver the cluster into a situation where replica A was missing op=5 and op=6, replica B was missing op=5 (but had op=6) and replica C was missing op=6 (but had op=5)", so that replica A "always directed a request for op=5 to B and for op=6 to C"; and "Without liveness mode, this would eventually resolve, and go undetected, when replica A is restarted and the retry counter is reset." This is the most instructive datapoint in this report for ox: the bug lived in a retry/repair scheduling interaction, and the only reason it persisted long enough to be detected is that the harness made the healing event (restart) impossible for a defined part of the run.

T6. A fuzzer has blind spots, and the maintainers published one. Source says (blind spots blog): "Jepsen found a correctness bug in what appeared to be a well-fuzzed component of the code: TigerBeetle's query engine." The culprit in the harness: queries were pre-registered with disjoint so "because of the common prefix for each query's target fields, the objects matching any given query are consecutive in each index. We have accidentally introduced a blind spot (!) in the fuzzer." Their conclusion: "When a fuzzer stops finding bugs, that doesn't mean its job is done—it may simply mean it has exhausted the particular slice of state space it can reach."

What it prevents: exactly what a green nightly simulation produces — a passing run that never had a chance of failing.

### 1.3 Antithesis: hypervisor-level determinism, and the amplification trick

Sources: vendor docs (1.0 above); vendor engineering blog https://antithesis.com/blog/deterministic_hypervisor/; vendor blog co-written with the etcd maintainer https://antithesis.com/blog/2026/causality_analysis/. These are vendor claims; treat capability statements accordingly.

A1. Requirements of the hypervisor shape, useful mainly as a boundary marker for what Shape A must do by hand. Source says (hypervisor post):

- One core per deterministic instance: "Each instance of the deterministic hypervisor runs on just one physical CPU core."
- Time is virtualized: "Every attempt to access a time source from inside the guest – reading TSC, reading HPET, etc. – returns a virtual time value computed by the hypervisor."
- The scheduler is itself a fault-injection mechanism: "Since the Antithesis platform controls the guest's scheduler, we can also use it as a fault injection mechanism (for example, via thread starvation)."
- Injection happens at I/O exchange points, not at every suspension: "The points in execution history where the guest ingests input from the Antithesis platform become possible branch points for future execution. Consequently, the external view of the exploration of a system is an input tree." Later: "we also added interrupt injection to 'push' actions into the guest when we wanted to preempt its current activity instead of waiting for the next predetermined i/o exchange point."
- Its cost, in the authors' account: "The PMC instructions retired count isn't quite deterministic, even in its special 'precision' mode. Based on our testing, about one in a trillion instructions would be miscounted due to some unknown quirk of the CPU."

A2. Causality analysis: replay one timeline, then re-run forward with different fault patterns to attribute the bug to particular faults. Source says: "We take a single timeline where we saw the bug and rewind time to various points. Then from each point we let Antithesis run the simulation forward multiple times, injecting different patterns of faults, and see if we still hit the bug."

What it caught, with numbers. Source says: an etcd bug "where etcd returned stale data to a client that requested the most up-to-date value of a key. It was only found once in about every 19 days of testing with Antithesis. That's with 12 hour runs in Antithesis every day, on 48 cores. So roughly 11,000 hrs of CPU time!" Then: "we checked the logs and found that they corresponded to points where Antithesis added faults: a container hang at the time of the first jump, and a network delay at the second. We tuned Antithesis to perform these types of faults more frequently, and started seeing the bug twenty times more often."

Inference: this is the strongest published argument that "more seeds" is not the only lever; targeted fault frequency is. It is also the only source I found that quantifies the search cost of a single bug (about 11,000 CPU-hours) rather than only the benefit.
### 1.4 The Rust reproductions, and what each one required

R1. madsim (used by RisingWave). Sources: project README https://github.com/madsim-rs/madsim; blog by its author at RisingWave, https://risingwave.com/blog/deterministic-simulation-a-new-era-of-distributed-system-testing/ and its sequel https://risingwave.com/blog/applying-deterministic-simulation-the-risingwave-story-part-2-of-2/.

Source says (madsim README): "MadSim is a Rust async runtime similar to tokio, but with a key feature called deterministic simulation. The main idea is borrowed from FoundationDB and sled simulation guide." and "However, implementing deterministic simulation is difficult. All I/O-related interfaces must be mocked during the simulation, and all uncertainties should be eliminated."

The blog enumerates four components: a global deterministic PRNG ("With the same random seed, the same execution sequence can be produced."); a timer that is "a priority queue sorted by timestamp"; a task scheduler whose queue "is designed to be first-in-random-out (FIRO) to explore potential concurrency issues"; and environment simulators for network and disk.

This is the clearest statement I found of how these systems get interleaving coverage: the run queue is not FIFO, it is randomized, so different seeds yield different schedules. That is the mechanism behind the mission's "force a schedule" question.

Interception: "Madsim intercepts some critical std APIs by overloading libc functions, such as gettimeofday, clock_gettime, getrandom, and sysconf, to provide deterministic time, random numbers, and system configuration in the simulation environment." For the rest, "For third-party libraries that cannot be made deterministic using this approach, manual patching and the [patch] feature in Cargo.toml are used to achieve code replacement."

What it caught (blog part 2): end-to-end simulation found "bugs caused by concurrency, including panics, deadlocks, and calculation errors"; the recovery-testing period found "panics caused by missing error handling, assertions based on erroneous assumptions, and result inaccuracies due to concurrency issues".

Cost and schedule, first-party numbers: "we were able to run simulation tests approximately 4-5 times faster than the actual execution"; CI "will execute each deterministic test with different seeds in parallel 16 times"; "we will also schedule daily tests on the main branch with no time constraints allowing us to run more iterations and cover more scenarios."

Stated limits: "Increasing the number of tests is not always the best way to uncover more bugs." and "Limited to Rust language projects: RisingWave has introduced more external data source connectors that may use other languages or depend on external processes. It is costly and less rewarding to develop simulators for each of them."

R2. turmoil (tokio ecosystem). Source: project README, https://github.com/tokio-rs/turmoil. Source says: "It runs multiple concurrent hosts within a single thread and injects 'hardship' — latency, drops, partitions, crashes, torn writes — into the simulated network and filesystem, under manual control or a seeded RNG." It ships drop-in replacements ("turmoil-net ... Drop-in replacement for tokio::net"; "turmoil-fs ... Drop-in replacement for std::fs / tokio::fs"). That is the same shape as ox's mock-capability plan, applied at library level.

R3. shuttle (and loom, which it contrasts with). Source: project README, https://github.com/awslabs/shuttle. Source says: "Shuttle avoids this issue by controlling the scheduling of each thread in the program, and scheduling those threads randomly. By controlling the scheduling, Shuttle allows us to reproduce failing tests deterministically. By using random scheduling, with appropriate heuristics, Shuttle can still catch most (non-adversarial) concurrency bugs even though it is not an exhaustive checker." and "Shuttle is not sound (a passing Shuttle test does not prove the code is correct), but it scales to much larger test cases than Loom." The README names the technique it implements: "A Randomized Scheduler with Probabilistic Guarantees of Finding Bugs."

R4. SlateDB DST: the cfg-gated short run plus a cfg-gated nightly run. Source: https://github.com/slatedb/slatedb/tree/main/slatedb-dst. Source says: "Everything in DST is deterministic, including the random number generator, the system clock, and the runtime. This means a failed test can be re-run with the same seed to reproduce the failure." Tests are "gated behind a cfg(dst) attribute" (plus cfg(tokio_unstable)), and "This crate also contains a longer-running test that's meant to be run every night. It is only run when slow, dst, and tokio_unstable cfgs are all set."

R5. sled's simulation guide: a prescriptive recipe, not evidence of a shipped simulator. Source: http://sled.rs/simulation.html. Source says: "A single Jepsen test can take 5 minutes. Let's run thousands per second using discrete event simulation!" The guide gives an eight-step recipe: write the algorithm as a state machine with the shape receive(msg, at) -> [(msg, destination)] plus tick(at); generate client requests; "stuff all messages / events in the system into a priority queue keyed on next delivery time"; iterate delivering; assign each outgoing message a delivery time deterministically "or drop it"; assert on observed request/response pairs; and minimize a failure by dropping initial requests. On the timing model: "the simplest to implement, and also the one that guarantees the freedom from the most bugs in the wild, is the asynchronous model, where any message can be arbitrarily delayed (maybe forever, dropped) or reordered with others."

I checked the current sled repository root through the GitHub contents API on 2026-10-04 and found no simulator crate or directory (entries included src, tests, fuzz, examples). So the guide is best treated as a design document that later projects (madsim, slatedb) credit and implement; I found no evidence in that listing that sled itself shipped it. That is an absence statement about one repository listing, not a claim about sled's history.

### 1.5 Three company write-ups that matter for the record-and-replay mechanics

D1. Dropbox Nucleus (company engineering blog, https://dropbox.tech/infrastructure/-testing-our-new-sync-engine). Source says, as a numbered recipe in the post: "At the beginning of a random test run, generate a random seed. Instantiate a pseudorandom number generator (PRNG) with that seed... Run the test using that PRNG for all random decisions, e.g. generating initial filesystem state, task scheduling, or network failure injection. If the test fails, output the seed." Plus: "Every night we run tens of millions of randomized test runs." and "When a regression sneaks in, CI automatically creates a tracking task for each failing seed, including also the hash of the latest commit at the time. If an engineer needs more logging to understand what happened in the test run, they can simply add it inline and re-run the test locally! It's guaranteed to fail again."

Two details that are easy to miss and mechanically checkable:

- Determinism requires killing hidden entropy in the language runtime: "Rust's default HashMap uses a randomized hashing algorithm under the hood... we override this behavior with a deterministic hasher to make sure all behavior is reproducible."
- The commit hash is part of the test input: "Note also the importance of the commit hash, as another type of 'test input' alongside the seed: if the code changes, the course of execution may change too!"

Their fake-I/O layer, Trinity, "alternates between scheduling Nucleus and scheduling itself on the main thread... aggressively agitates the system by modifying the local and remote filesystems, intercepting Nucleus's asynchronous requests and reordering responses, injecting filesystem errors and network failures, and simulating crashes." And it "verifies its own determinism by re-running the same test (with the same seed) and asserting that the same final state is reprodu[ced]".

What it caught: "it was CanopyCheck that exposed the Archives/Drafts/January directory cycle bug ... CanopyCheck was able to find this condition where applying a local move and a remote move together created a cycle. The seed then triggered an assertion error within our tree data structure and failed the test."

D2. Resonate (maintainer blog, https://journal.resonatehq.io/p/dst-finds-a-bug). Source says: "Resonate DST (deterministically) randomly generates requests and fires them off against the server. We use a seed to configure the test so that if we see a failure on GitHub Actions we can easily reproduce the same failure locally." Reproduction is a command the CI issue carries: "go run ./... dst run --seed 23496 --ticks 1000". Their oracle is a linearizability checker: "Resonate uses Porcupine ... to verify the linearizability of the concurrent requests sent and responses received by the test."

What it caught: a real atomicity bug. The run reported "DST is non linearizable"; the cause was that "the create promise query has an on conflict clause that effectively undoes the atomicity guarantees of the transaction. So when the CreatePromiseAndCallback request occurs the promise is not created, but the callback is."

D3. CockroachDB with Antithesis (company engineering blog, https://www.cockroachlabs.com/blog/demonic-nondeterminism/). Source says: a violated-invariant crash "first showed up on our radar in 2021... it was autofiled by Sentry's crash reporting module" and "this failure mode never appeared in any of our extensive test runs." After adopting Antithesis, "Fortuitously, one of the scenarios terminates in exactly the same, elusive state as seen in the log below", and "Many rinse-and-repeat cycles later, the root cause, its fix, and a reproducing unit test have emerged." Their summary of the mechanics: "Without deterministic reproduction, conventional debugging and (stress) testing don't yield an effective strategy; for 'one-in-a-million' type of bug, it's really no different than pure chance." They also give the minimal single-machine recipe: "ptrace, a logical clock, a single-threaded scheduler, and a RAM disk is roughly all you need for deterministic debugging on a single machine; beyond a single machine, network is a great non-determinizer."

One lesson that bears on ox's ADRs: "while the Parallel Commit protocol was verified using TLA+, the model is an underapproximation of the actual implementation. Specifically, the TLA+ specification doesn't model the above scenario."

### 1.6 "Fault injection at every suspension point": what the sources actually say

I did not find that phrase, or that exact requirement, in any primary source. What the sources describe is:

- FDB: explicit buggify sites in code (25% activation per run, 25% firing) plus network/disk/machine faults and randomized event times (F2).
- TigerBeetle: a dice roll "on every tick" for crashes, restarts, packet drops and disk corruption (T3).
- Antithesis: injection at guest I/O exchange points (VMCALL) plus interrupt injection, and thread starvation through the guest scheduler (A1).
- madsim: randomness at every task-scheduling decision, because the ready queue is FIRO rather than FIFO (R1).
- Dropbox Trinity: reordering and error injection at the asynchronous request boundary, driven from a single thread (D1).
- sled's guide: a deterministic delivery time, or a drop, assigned to every outbound message (R5).

Inference, stated as inference: for a cooperative-fiber runtime like Eio, the useful equivalent is two mechanisms, not one — (a) every scheduling decision is a seeded random choice (madsim's FIRO), and (b) every mocked capability consults the seeded PRNG on every operation (FDB's buggify sites, moved into the mock). Section 2 turns this into a design.

### 1.7 The OCaml reality: what exists today, and what does not

O1. Eio has a determinism design note, and it is a guarantee with stated limits.

Source: project README, https://github.com/ocaml-multicore/eio/blob/main/README.md, section "Design Note: Determinism" (verified byte-for-byte in the v1.6 source tree; the installed eio is 1.6). Source says:

- "Within a domain, fibers are scheduled deterministically."
- "Programs using only the Eio APIs can only behave non-deterministically if given a capability to do so from somewhere else."
- "For example, Fiber.both f g always starts running f first, and only switches to g when f finishes or performs an effect that can switch fibers."
- "Performing IO with external objects (e.g., stdout, files, or network sockets) will introduce non-determinism, as will using multiple domains."
- "Note that traceln is unusual. Although it writes (by default) to stderr, it will not switch fibers. ... This means that adding traceln to deterministic code will not affect its scheduling."
- "In particular, if you test your code by providing (deterministic) mocks then the tests will be deterministic. An easy way to write tests is by having the mocks call traceln and then comparing the trace output with the expected output."
- "Note: this only applies to the high-level APIs in the Eio module. Programs can behave non-deterministically when using Eio_unix or the various Low_level APIs provided by the backends."

Why this matters for ox: the first two sentences are the licence for a simulation harness; the last one is why ox's current harness (lib/test/ox_test.mli, which states "The operating system is NOT virtualized.") cannot be the simulation harness.

O2. Eio_mock.Backend.run_full is already a deterministic, single-threaded scheduler with a fake clock and no I/O. This is the most important local finding.

Source: source code, https://github.com/ocaml-multicore/eio/blob/main/lib_eio/mock/backend.ml (verified in the v1.6 tarball). Its scheduling loop is:

    let rec schedule t : exit =
      match Lf_queue.pop t.run_q with
      | Some f -> f ()
      | None ->
        (* Nothing is runnable. Try advancing the clock. *)
        if Clock.Mono.try_advance t.mono_clock then schedule t
        else [Exit_scheduler]

(where the final expression is the polymorphic variant Exit_scheduler). Fibers are resumed through a handler for exactly three Eio effects (Eio.Private.Effects.Suspend, Fork, Get_context), with a FIFO run queue and one deliberate ordering choice:

    (* Arrange for the forking fiber to run immediately after the new one. *)
    Lf_queue.push_head t.run_q (Suspended.continue k);

Consequences, all visible in that file and its interface:

- No poll, no timers, no real clock, no second domain. The mock backend's interface (lib_eio/mock/backend.mli in the same tree) says: "A dummy Eio backend with no actual IO." and "This backend does not support the use of multiple domains or systhreads, but the tradeoff is that it can reliably detect deadlock, because if the run queue is empty then it knows that no wake up event can be coming from elsewhere." Deadlock is reported as the exception Deadlock_detected.
- Time is a data structure ox owns: Eio_mock.Clock's interface says "The time is initially set to 0.0 and doesn't change except when you call advance or set_time.", and advance "sets the time to the next scheduled event (adding any due fibers to the run queue)". The implementation (lib_eio/mock/clock.ml) stores sleepers in a Psq priority search queue, so wake order at equal times is data-structure order, not OS order.
- run_full additionally supplies a mock environment whose "mock monotonic clock ... advances automatically when there is nothing left to do", and Eio_mock.Domain_manager "runs everything in a single domain, allowing tests to remain deterministic" (verbatim from Eio's CHANGES.md, https://github.com/ocaml-multicore/eio/blob/main/CHANGES.md, entry for the PR that added it).

So the answer to "is there a deterministic scheduler in OCaml/Eio" is: yes, in the test package, and it is what Eio_mock uses by default. It is deterministic but not controllable: the schedule is a function of where the program suspends, and there is no seed and no way to request a different interleaving.

O3. What Eio_mock can and cannot control today (from the installed 1.6 interface, eio/mock/eio_mock.mli).

Can:
- Flows: Eio_mock.Flow.make / on_read / on_copy_bytes / set_copy_method, scripted with Eio_mock.Action values: Return, Raise, Await, Yield_then, Run. Yield_then and Raise are the fault-injection primitives that exist; Run lets arbitrary code, including a seeded decision, execute at that point.
- Networks: Eio_mock.Net.make / listening_socket with on_connect / on_listen / on_datagram_socket / on_getaddrinfo / on_getnameinfo / on_accept, each taking a list of actions, so connection failures and accept delays can be scripted.
- Clocks: Eio_mock.Clock and Eio_mock.Clock.Mono with make / advance / try_advance / set_time.
- Domains: Eio_mock.Domain_manager, a single-domain fake.
- A backend-level simulated failure constructor (Simulated_failure added to Eio.Exn.Backend.t).

Cannot:
- Be seeded or randomized. Eio_mock.Handler's API is a script (make / set_handler / seq / run / run_default_action); the same script runs on every execution, and there is no PRNG in the mock package (grep for "seed" in lib_eio/mock of the eio-1.6 tree: 0 hits).
- Provide a full stdenv. run_full's environment type is only <clock; mono_clock; debug; backend_id>, not Eio.Stdenv.t, so code that takes fs, net, process_mgr or domain_mgr from the environment cannot run under it unchanged.
- Explore schedules. There is no reordering; the FIFO queue plus the fork-to-head rule fixes the interleaving.
- Generate workloads. There is no operation generator; a test writes its own scenario.

O4. A seeded, schedule-exploring scheduler is feasible, and Eio already contains one twice.

- The effect interface is public. Eio's public interface (lib_eio/eio.mli, v1.6) exposes "module Private = Eio__core.Private" under the heading "Provider API for OS schedulers" with the doc "API for use by the scheduler implementation."
- The effects are exactly three (lib_eio/core/eio__core.mli): Suspend carrying (Fiber_context.t -> 'a enqueue -> unit); Fork carrying Fiber_context.t * (unit -> unit); and Get_context. A scheduler needs nothing else, because promises, streams, mutexes, conditions, switches and cancellation are built on top of those.
- A scheduler is short. Eio_mock.Backend is 116 lines. Eio's own test suite contains a second, 21-line one: lib_eio/tests/dscheck/fake_sched.ml, which handles Suspend and cancels the fiber's context; it drives Eio's semaphore, sync channel, condition and pool implementations under dscheck. Its purpose, from fake_sched.mli: "run fn () in a new fiber and returns its context so it can be cancelled."
- The ecosystem teaches the technique: miou's lib/scheduler.mld is a tutorial, "A simple scheduler with OCaml 5", built on effects (https://github.com/robur-coop/miou/blob/main/lib/scheduler.mld).

Inference: what does not exist is a seeded scheduler with a chosen queue discipline (madsim's FIRO) and a body of workloads that use it. Nothing in the platform prevents building one; it is on the order of a few hundred lines of OCaml plus the harness around it. Its risk is concentrated in one place: it may use only Eio.Private, which Eio documents as provider API and does not promise to keep stable. I found no statement in Eio's README, HACKING.md or CHANGES.md about the stability policy of Eio.Private; that is a real, unquantified risk (see section 4).

O5. What OCaml does instead today, and each mechanism's stated limit.

Q1. QCheck gives seeds and a two-speed run.
Source: QCheck source, https://github.com/c-cube/qcheck (src/runner/QCheck_base_runner.ml). Its CLI has "-s", "--seed" documented as "set random seed (to repeat tests)" and "--long" documented as "run long tests"; the library's long_factor is documented in QCheck.mli as "the factor by which to multiply count, max_gen and max_fail when running a long test (default: 1)". The runner prints "random seed: N" when it picks one. So "print the seed" and "short default run plus long nightly run" are already native to the OCaml property-testing stack ox uses in test/stress.

Q2. Alcotest gives the same two-speed split for example-based tests.
Source: installed alcotest 1.9.0+ox engine (alcotest/engine/config.ml and model.ml): tests carry a speed level of Quick or Slow; the CLI flag is "-q", "--quick-tests", documented as "Run only the quick tests.", with environment variable ALCOTEST_QUICK_TESTS; selection compares the test's level against the requested one (engine/core.ml). This is the installed package; I did not fetch the upstream page for the same text.

Q3. qcheck-lin and qcheck-stm test concurrency, but with real domains and repetition rather than a controlled schedule.
Source: multicoretests README, https://github.com/ocaml-multicore/multicoretests/ (packages qcheck-lin and qcheck-stm; qcheck-stm 0.10 changelog at https://ocaml.org/p/qcheck-stm/0.10/CHANGES.html). Source says Lin "performs a sequence of random commands in parallel, records the results, and checks whether the observed results can be linearized and reconciled with some sequential execution"; STM "checks whether the observed results are linearizable by reconciling them with a sequential execution of a model description". Each instance "consists of a 'sequential prefix' of calls ... followed by a spawn of two parallel Domains".

Their repeatability section is the honest statement ox should plan around: "When rerunning a test to shrink/reduce the test input, QCheck thus starts from the same Random seed to limit non-determinism. This is however not suffient for multicore programs where CPU scheduling and garbage collection may hinder reproducibility." Their answers: "Lin and STM primarily uses test repetition to increase reproducibility and it is sufficient that only a single repetition triggers an issue"; the repeat combinator (util.mli: "This is handy if the property outcome is non-determistic, for example, if it depends on scheduling."); QCheck's retries parameter; and an amplification hack: "Since PR#540 the Lin_thread and STM_thread modes both utilize a Gc.Memprof callback to trigger more frequent context switching at allocation points, effectively increasing the chance of surfacing Thread-based concurrency issues." (The qcheck-stm 0.8 changelog records the same change as "Significantly increase the probability of context switching in Lin_thread and STM_thread by utilizing Gc.Memprof callbacks.")

Inference: with real Domain.spawn you get neither reproducibility nor schedule control; you buy coverage with repetition. That is the current OCaml baseline a simulation harness would improve on.

Q4. dscheck is a real model checker, but for a different execution model.
Source: project README, https://github.com/ocaml-multicore/dscheck/. Source says: "DSCheck explores interleavings of a user-provided program and helps ensure that its invariants are maintained regardless of scheduling decisions", using dynamic partial-order reduction ("DSCheck aims to cover exactly one interleaving per trace"). Its soundness preconditions are explicit: "For model-checking to be sound, tested program must meet the following conditions: Determinism... Tested programs cannot have races between non-atomic variables... Domains can communicate through atomic variables only... Tested programs have to be at least lock-free." Usage requires replacing Atomic with Dscheck.TracedAtomic, so the tested implementation is compiled against a shadowing atomic library; saturn's test README documents the copy rule ("every datastructure implementation is copied in its respective tests directory and compiled using the dscheck atomic library", https://github.com/ocaml-multicore/saturn/blob/main/test/README.md).

Eio uses dscheck on its own lock-free internals: HACKING.md says "lib_eio/tests/dscheck uses dscheck to perform exhaustive testing of all atomic interleavings", and adds a cost caveat: "At the time of writing, dscheck has some performance problems that make them unusable by default, so you must use the version in https://github.com/ocaml-multicore/dscheck/pull/22 instead." The tests are wired to a non-default dune alias (lib_eio/tests/dscheck/dune defines the alias dscheck), not to the default test run.

Q5. Crowbar/AFL covers protocol parsers, not schedules.
Source: crowbar source, https://github.com/stedolan/crowbar (src/crowbar.ml). Options: "-s", "--seed" documented as "The seed (an int64) for the PRNG. Use as an alternative to FILE when running in non-AFL (quickcheck) mode."; "-r", "--repeat", default 5000; and a positional FILE, which in AFL mode is the test case ("Re-run a test by supplying the test file here"). In repeat mode the runner derives a fresh per-iteration seed from a seed source and keeps only the worst status; I did not find code that prints that per-iteration seed, although it does print the failing generated input. Worth knowing before promising "every failure has a replayable seed" in ox: crowbar's replay artifact is the input; its seed flag is for whole-run reproduction.

Q6. Eio's own tests are golden traces.
Source: HACKING.md and the tests directory of the v1.6 tree. Eio's cross-platform tests are mdx Markdown files (tests/*.md, e.g. tests/mocks.md, tests/time.md) that run code and compare traceln output; the README determinism note recommends exactly that ("having the mocks call traceln and then comparing the trace output with the expected output"), and mdx markers exist for the genuinely non-deterministic parts. Brute-force stress tests live in stress/ ("try to trigger races by brute force") and AFL fuzzers in fuzz/.

O6. The gap, stated compactly.

    component                   available today in OCaml/Eio              missing
    ------------------------------------------------------------------------------------
    single-thread scheduler     Eio_mock.Backend.run_full (deterministic)  seeded / alternative schedules
    fake clock                  Eio_mock.Clock (+ auto-advance)             fault-aware clock, time budgets
    fake network                Eio_mock.Net (scripted)                     seeded latency/drop/partition
    fake disk                   none; Eio_mock has no fs mock               a fake Eio.Fs.dir_ty
    fake randomness             none; Eio supplies secure_random            a seeded capability
    replayable seed             QCheck/Alcotest/crowbar -s; ox prints one   a seed that reaches schedule and faults
    fault injection             Eio_mock.Action Raise / Yield_then          a policy: where, how often, at what rate
    workload generation         QCheck generators; qcheck-lin/STM             workloads that also drive faults
    short vs long run           QCheck --long/long_factor; Alcotest -q      a nightly job in this repository
    oracles                     Alcotest checks; QCheck properties;         a per-step invariant checker
                                Lin/STM model checkers; dscheck

Also verified locally, and positive: ox already has the skeleton. test/stress/core_properties.ml runs "Real Eio fibers on a virtual clock" under Eio_mock.Backend.run_full and checks Ox laws with QCheck2; test/stress/stress_support.ml defines seed ~default () reading --seed or OX_STRESS_SEED and prints "OX_STRESS_SEED=%d"; test/stress/dune already runs each storm under "timeout 60" with a fixed seed behind the stress alias and depends on (env_var OX_STRESS_SEED), so changing the seed re-runs the rule. What is missing is (a) the seed reaching the mock behavior and the schedule, (b) fault injection, (c) the long run, and (d) the determinism self-check.
---

## 2. Things ox should adopt, ranked

Ranking rule: (reach over ox's known bug classes) x (cheapness of the enforcement mechanism) / cost. Each item names the concrete shape and the mechanical check that keeps it true, because ox's stated goal is that wrong code fails to compile, fails a gate, or fails a deterministic test.

### 2.1 A seeded simulation harness, one module, on top of Eio_mock.Backend.run_full

Shape (test-only module, e.g. test/sim/ox_sim.mli, or lib/test/ox_sim.mli if every package's tests need it):

    module Ox_sim : sig
      type t
      type fault =
        [ Fail of exn            (* an operation fails although it usually succeeds *)
        | Delay of Ox.Duration.t (* an operation that is usually fast is slow *)
        | Yield                  (* force an extra reschedule here *)
        | Partial of int         (* return fewer bytes than the buffer allows *)
        | Drop                   (* a message never arrives *)
        | Reorder                (* a message arrives after a later one *)
        ]
      val run :
        ?seed:int ->                 (* default: printed, from OX_SIM_SEED or --seed *)
        ?faults:fault list ->        (* swarm mask; default: random subset *)
        (t -> 'a) -> 'a
      val seed : t -> int            (* always printed in the failure report *)
      val random : t -> Random.State.t
      val decide : t -> fault -> float -> bool   (* buggify: decides and records *)
      val trace : t -> string        (* digestible schedule/decision log *)
    end

Behavior:
- Run inside Eio_mock.Backend.run_full, so the schedule is single-threaded, the clock is virtual, and deadlock is detected instead of hanging. Every fiber-fork decision stays Eio's; the harness does not reorder anything in its first version.
- The seed feeds one Random.State.t, and every mock capability consults it through decide for every operation, in the style of FDB's buggify sites and TigerBeetle's per-tick dice roll.
- On failure, print the seed and the exact rerun command, and write the decision log. Resonate's CI issue with "dst run --seed 23496 --ticks 1000" is the model.
- Seed/replay plumbing already exists in ox: test/stress/stress_support.ml prints OX_STRESS_SEED and accepts --seed. Extend it rather than inventing a second convention.

What it prevents: the class of bug that needs a rare ordering of capability-level events (a read that returns half a frame; a wakeup that arrives one tick after the timeout; a cancellation delivered exactly at a suspension point). Under Eio_mock today the script is the same on every run, so those orderings are never produced unless a human writes them by hand.

Cost: one small module plus one fake per capability ox actually consumes. Eio_mock already supplies clock, network and flow fakes; ox needs a fake filesystem (Eio_mock has none) and a seeded capability for Cap_sys.urandom and Cap_stdlib.make_self_init. No new dependency: eio.mock is already used by test/stress.

Check: a test that fails the build when a capability has no fake (item 2.5), plus the determinism self-check (item 2.2).

### 2.2 A determinism self-check (the "unseed")

Shape: at a configurable rate (FDB uses about 1%) run the same scenario twice in one process with the same seed and assert that (a) the trace digest is equal and (b) the PRNG state after the run is equal. Surface a violation as a test failure naming the seed and the first differing trace line. FDB does this with its double-run "unseed" comparison; Dropbox's Trinity "verifies its own determinism by re-running the same test (with the same seed) and asserting that the same final state is reprodu[ced]".

Why ox needs it more than FDB did: FDB had to fight C++ toolchains; ox has to fight the OCaml runtime around it — Random.self_init or Random.State.make_self_init, Hashtbl.create with randomized hashing, Unix.gettimeofday or Sys.time read outside a clock capability, a finalizer or GC-dependent ordering, a stray Domain.spawn, a real file or socket a test forgot to fake. Each of those turns the harness silently into a flaky suite, and a digest comparison is the only cheap detector.

Cost: small. A digest over the recorded trace plus the PRNG position; double runtime on the checked fraction.

Check: the test itself, at a low rate in the default alias, so a determinism regression is caught on the commit that introduces it.

### 2.3 A fault-injection policy at every mocked operation, with a per-run mask

Shape: a fault class per boundary, decided from the seed, recorded, and enabled per run by a swarm mask (FDB: "enables and disables a different random subset of buggification points"):

    clock:  Delay (sleep longer or shorter than asked), Wake_late (wake after a timeout fired)
    flow:   Partial (half frame), Fail (EIO), Eof (early EOF), Yield
    net:    Drop, Reorder, Delay, Partition, Connect_fail
    cancel: Cancel_at (inject cancellation at the next suspension)
    domain: Run_inline (Eio_mock.Domain_manager already runs everything in one domain)

Two rules matter more than the fault list:
- Fault rate is a tuning problem, not a maximum. FDB warns that an excessive fault rate drives the system into a small state space; the Antithesis/etcd story shows the opposite lever, raising the rate of the two faults that mattered until the bug appeared about twenty times more often.
- Every decision is recorded, so a failure can be attributed. Without that, a failing seed is a random number, not a diagnosis.

Cost: medium. Each fault has to be implemented inside a fake, and each fake needs a test that the fault is reachable; a fault that can never fire is worse than no fault, because it is a false guarantee.

Check: a coverage counter per fault class, asserted non-zero on the long run (item 2.9).

### 2.4 A seeded randomized scheduler for ox's own fiber-level primitives

This is the item that answers "can anything control fiber interleaving in OCaml": yes, with a test-only scheduler over Eio.Private.Effects (Suspend, Fork, Get_context), exactly as Eio_mock.Backend and Eio's own lib_eio/tests/dscheck/fake_sched.ml already do — but with a seeded queue discipline (madsim's FIRO: the ready queue is first-in-random-out) instead of FIFO.

Shape: test-only module, roughly 200-400 lines: a run queue, a virtual clock, and the three-effect handler; a queue-discipline parameter; a switch budget per run. Used as:

    Ox_sim_sched.run ~seed ~switches:10_000 (fun () -> ...code under test...)

Targets, in order: Ox.Scope (finalizer ordering, cancellation at boundaries), Ox.Actor and Ox.Agent (messages, cancellation, accounting), Ox.Schedule and Ox.Rate_limiter (the components most likely to hide a retry/timer interaction of the VOPR-liveness kind), channels and streams.

What it prevents: interleaving bugs inside fibers that never touch a mocked capability — the class Eio_mock cannot reach and that Domain-based QCheck tests can only sample.

Cost: high, and the risk is honest: it may use only Eio.Private, whose stability Eio does not state (section 4). Mitigations: keep it under test/, never in lib/ (enforce with a dune-dependency rule in the style of scripts/caps-gate), and keep the FIFO Eio_mock path as the default so the suite still runs if the private API moves.

Check: a dune gate forbidding lib/ from depending on the sim scheduler, plus the laws ox already asserts in test/stress/core_properties.ml, re-run under many seeds.

### 2.5 A determinism contract for every foreign boundary, enforced by the compiler

Shape: a record (or object) of fakes indexed by capability, so that adding a capability to Cap.all_caps is a compile error until its fake exists:

    type sim_env = {
      clock; mono_clock; random; time;
      fs; network; process; signal; env;
      stdin; stdout; stderr; exit; fork; exec; chdir; tmp;
    }

The capability rows in lib/caps are already structural, and tests already mint a powerbox through Ox_test.powerbox (); the sim harness is the second consumer that needs the same rows to have deterministic implementations. Honest limitation: a capability token grants permission, not behavior — Cap_sys.urandom reads /dev/urandom no matter who holds Cap.random — so the simulation fakes must be a parallel wrapper set, and the gate must ensure production code never reaches the OS wrapper on a simulated path. That is a design decision for ox's authors; the mechanical part is that the fake set is indexed by the same rows.

What it prevents: a new capability quietly becoming a nondeterminism leak. That is FDB's "unable to test third-party libraries or dependencies, or even first-party code not implemented in Flow" and RisingWave's "limited to Rust language projects" limitation, in OCaml form.

Cost: small per capability; the ongoing cost is discipline at the seam.

Check: adding a capability without a fake stops the sim harness compiling; plus a test that every fake is exercised at least once per long run.

### 2.6 Model-based tests for ox's pure state machines (qcheck-stm / Lin)

Shape: an STM.Spec model per state machine (Actor/Agent lifecycle, Channel, Schedule, Rate_limiter), with agree_test_par for parallel agreement and STM_sequential.agree_test for the sequential law; Lin for the pure data structures. ox already depends on qcheck-core in test/stress, and test/stress/core_properties.ml already states the property shapes.

Honest scope: these tests run two real Domains; multicoretests documents that CPU scheduling and GC "may hinder reproducibility", and they compensate with repetition plus a Gc.Memprof context-switch amplifier. So STM/Lin complement items 2.1-2.4; they are strong at semantic errors (the model disagreement is the oracle) and weak at schedule coverage.

Cost: a new dependency (qcheck-stm, qcheck-lin) under ADR-0005; unverified whether they build on OCaml 5.4.0+ox (neither is installed in this switch; see section 4). Model authoring is the real cost: a few hundred lines of speculative code per API.

Check: the STM suite under the stress alias with a fixed seed, plus the nightly long factor.

### 2.7 Keep the short run short and give the long run its own budget

Shape: the knobs already exist. Default: dune test runs a small seed count (for example 16 seeds x 2 fault masks) under Alcotest's Quick level (-q) and QCheck's default count. Nightly: QCheck --long (long_factor), a large seed sweep, every fault class enabled at a high rate, and no 60s per-test timeout (every rule in test/stress/dune currently carries "timeout 60").

Make the split explicit in the spec and the dune file with two aliases (for example sim and sim-long), and record the exact commands in the repository's documentation. SlateDB's cfg(dst)/cfg(slow) gating and RisingWave's "daily tests on the main branch with no time constraints" are the same pattern; RisingWave also gives the reason to keep the PR run short: "each PR can complete all tests within 20 minutes".

Cost: near zero in code, real in CI time. The failure mode to watch, which RisingWave reports, is the long run growing until it exceeds its budget; the fault rate is the knob to trade intensity for time.

### 2.8 Oracles that run at every step, not only at the end

Shape: per-step invariant checks in the style of dscheck's Atomic.every and TigerBeetle's checkers: after each simulated event, assert the accounting laws (no fiber left behind — ox already has Ox_test.assert_no_fibers_left — Cause tree shape, buffer ownership, outstanding request counts, one reader per buffer). Where ox wants an oracle in production, keep it there, as TigerBeetle keeps thousands of assertions on in production.

Caution from the sources: checkers themselves go wrong. Among the tigerbeetle pull-request titles returned by search are "vsr: fix VOPR false positive", "vopr: fix multiple false positives", "vopr: fix false positive", and "vopr: false positive during upgrades"; and the blind-spot post shows a workload that silently stopped covering a dimension. So every checker needs a test with a deliberately violated input, and every fault class needs a reachability counter (2.9).

Cost: low per check; the false-positive tax is ongoing.

### 2.9 A nightly honesty gate: coverage of faults and states

Shape: FDB's conditional coverage, in miniature. The harness counts per run which fault classes fired, which mock operations were reached, and which checkers ran. The nightly job fails when a class that the configuration says should fire never fired, or when a counter the spec names as required stays at zero.

What it prevents (T6): a green simulation that has drifted into a blind spot. It is the cheapest defence against the belief that "our nightly is green, we are safe" — a belief the TigerBeetle maintainers publicly falsified about their own fuzzer.

Cost: small counters plus a threshold table in the spec.

### 2.10 Golden traces for a pinned seed (the reviewable artifact)

Shape: an mdx or cram test that runs one pinned seed against the sim harness and compares the trace, in the convention Eio itself uses (README: mocks "call traceln and then comparing the trace output with the expected output"; tests/*.md). Because traceln does not switch fibers, adding trace lines cannot change the schedule.

Why: it puts a schedule under review. A trace diff is a behavior change that a reviewer — a human reading interfaces, or an agent reading a diff — can see. Without it, changing a mock or a retry path changes every downstream schedule silently.

Cost: low; brittleness is bounded by pinning one seed and keeping the trace short.

### Ranking summary

    rank  item                                          value  cost   enforcement
    ----------------------------------------------------------------------------------
    1     2.1 seeded sim harness on Eio_mock              high   low    test
    2     2.2 unseed determinism self-check               high   tiny   test (default run)
    3     2.3 seeded fault policy + per-run mask          high   med    test + coverage counter
    4     2.5 determinism contract per capability         high   small  compile error
    5     2.8 per-step oracles                            high   low    test
    6     2.9 nightly honesty gate                        med    small  nightly job
    7     2.7 short/long split                            med    tiny   dune aliases
    8     2.10 golden trace for a pinned seed             med    small  mdx test
    9     2.6 qcheck-stm / Lin models                     med    med    stress alias
    10    2.4 seeded randomized scheduler (Eio.Private)   high   high   test-only module + dune gate

Ordering note: 2.4 is the most powerful item and deliberately last. It pays off only once 2.1 and 2.3 exist (the fakes and the seed plumbing), it is the only item with a platform-stability risk, and the Eio_mock path must stay the default so the suite never depends on a private API to run at all.
---

## 3. Things that look relevant but do not apply

1. An Antithesis-style deterministic hypervisor (or a VM/CPU-level replay layer, or rr-style OS record/replay). It makes arbitrary native code deterministic by controlling one physical core, virtualizing time at the TSC/HPET level, and injecting input at VMCALL exchange points (source: Antithesis hypervisor post). Its stated unit of reproducibility is "the state of the entire system/experiment/workload as an interconnected whole". ox is a library kernel inside an OCaml process; adopting this would mean moving the test boundary below the language, and the vendors themselves report that full instruction-level determinism is imperfect (one in about a trillion instructions miscounted on their own hardware). The interesting content of that post for ox is not the hypervisor but the two facts it establishes: the scheduler is a legitimate fault-injection point, and reproducibility must be engineered at every boundary, not only at the network.
2. dscheck applied to ox's fiber code. dscheck is real and Eio uses it, but its documented soundness preconditions do not hold for typical ox code: "Domains can communicate through atomic variables only", "Tested programs cannot have races between non-atomic variables", "Tested programs have to be at least lock-free". ox's concurrency is cooperative fibers plus switches, conditions and streams, not lock-free atomic structures. It also requires compiling the implementation against Dscheck.TracedAtomic (a copy of the source into the test directory, as saturn documents), and Eio's HACKING.md records a performance caveat requiring a patched dscheck (PR 22), which is why Eio's dscheck tests sit behind a non-default dune alias. It applies to a narrow slice: a lock-free structure inside ox, if one is ever added.
3. Loom-style exhaustive state-space exploration, TLA+ specifications, or the Iris/Zebre proofs that Eio's own scheduler has attracted. Exhaustive methods scale to small models, and CockroachDB's account is the concrete warning: "while the Parallel Commit protocol was verified using TLA+, the model is an underapproximation of the actual implementation. Specifically, the TLA+ specification doesn't model the above scenario." Nothing here replaces testing the real implementation; ox can keep such work as separate evidence, not as the concurrency gate.
4. madsim's two interposition tricks: overloading libc functions (gettimeofday, clock_gettime, getrandom, sysconf) and patching dependencies with Cargo. OCaml has no equivalent supported global interposition, and cargo-style patching of third-party crates has no counterpart in opam/dune that would keep determinism. The ox-shaped substitute is the capability signature (lib/caps plus Eio's explicit values): the call site that reads the clock or the randomness must receive a capability, and the caps-gate already refuses raw calls. This is why item 2.5 is a compile-time contract rather than an interposition layer.
5. Jepsen-style external fault injection. Its own practitioners' evaluation in the FDB paper is that such approaches "lack deterministic reproducibility", and the Cockroach post's framing is that for one-in-a-million bugs external stress testing "is really no different than pure chance". ox also has no multi-node deployment to point Jepsen at. It becomes relevant only if ox grows a network service with a real deployment, and even then it complements simulation rather than substituting for it (TigerBeetle's Jepsen engagement found a bug its four query fuzzers missed, and then the fix was to improve the simulator's workload, not to keep Jepsen running forever).
6. Gc.Memprof context-switch amplification. qcheck-stm uses it "to trigger more frequent context switching at allocation points" for Lin_thread/STM_thread, because with real threads there is no schedule control. It is a workaround for the absence of item 2.4, not a technique ox should adopt on purpose; if ox keeps Domain-based tests, it is a legitimate fallback knob there.
7. FDB's simulated cluster topology and machine-level models (drive space, rack and datacenter failures, IP address changes, swizzle-clogging). ox has no cluster, no racks and no disks of its own; the transferable part is only "model the environment your code trusts, and inject faults at that model". Building a cluster simulator for ox would be inventing an environment the library does not have.
8. "Fault injection at every suspension point" taken literally, as a design target. No primary source states it, and it is not obviously implementable or useful as written: FDB injects at explicit buggify sites and at network/disk operations, Antithesis injects at I/O exchange points and via interrupts, TigerBeetle rolls dice per tick, madsim randomizes task-scheduling choices. The precise, implementable forms are the two mechanisms in section 1.6 (seeded scheduling decisions and seeded per-operation decisions), and those are what items 2.3 and 2.4 build.
9. The three-way distinction between "the schedule is deterministic", "the schedule is reproducible", and "the schedule is explorable". Sources that only claim the first two (Eio's README, Eio_mock, SlateDB, Resonate) are not evidence that interleavings are being explored. The only sources here that describe actual schedule exploration are madsim's FIRO queue, dscheck's DPOR, and Antithesis's branch exploration. ox's plan should not claim more than it implements.

## 4. What I could not find out

Stated as absences, not filled in:

1. I found no OCaml project that reproduces FoundationDB-style deterministic simulation for Eio (or for OCaml generally): no framework, no library, no write-up. Searches run: "deterministic simulation testing OCaml effect handlers scheduler", "ocaml-multicoretests Lin STM dscheck", "dscheck OCaml 5 model checker README", "qcheck-stm state machine testing OCaml", "Eio OCaml deterministic scheduler testing Eio_mock clock". This is absence of evidence from those searches plus reading the Eio, miou, dscheck, multicoretests and qcheck sources; it is not proof that nothing exists in private repositories.
2. The stability policy of Eio.Private. Eio documents it as "API for use by the scheduler implementation" but I found no statement in the README, HACKING.md or CHANGES.md about compatibility guarantees. Item 2.4 depends on this and I cannot price that risk.
3. Whether a user-written scheduler can be plugged into the real runtime. The mock backend supplies only a four-method environment (clock, mono_clock, debug, backend_id), and I did not verify whether Eio.Stdenv.t can be constructed outside Eio's own backends, nor whether Eio_main could be pointed at a custom event loop. So "a deterministic scheduler is feasible" is verified for the mock-shaped subset and unverified for full programs that need fs/net/process_mgr/domain_mgr.
4. Whether Eio's own test suite contains a determinism self-test. I grepped the v1.6 tree for "determinis" and found only the README design note, the CHANGES entry about the mock domain manager, and mdx "non-deterministic=output" markers. I found no test asserting that the same program produces the same trace twice.
5. What FDB's "about a 10-1 factor of real-to-simulated time" means directionally. The surrounding sentence implies fast-forward, but the phrase itself is ambiguous and I did not resolve it; I quote it rather than interpret it.
6. What "unseed" means, precisely. The FDB wiki says "the unseed is the last random number generated", while the talk describes checking "what the next random number it would have been generated would have been". Both are consistent with a PRNG fingerprint; they are not consistent with each other, and I did not find a third source to settle it.
7. Whether qcheck-stm, qcheck-lin or dscheck build and run on this switch (OCaml 5.4.0+ox). None is installed, and I did not attempt an install. Any adoption of item 2.6 must start with that check.
8. Whether crowbar prints the per-iteration seed after a failure in repeat mode. I read the runner and did not find it; the failing generated input is printed, and -s/--seed reproduces a whole run. I did not run crowbar to observe its output.
9. Any engineering-effort number for building a simulation harness. The nearest quantitative statements I found are RisingWave's "painful debugging period of two months" while recovery testing matured, RisingWave's CI budgets (20 minutes per PR; 16 parallel seeds), FDB's per-night volume, and Antithesis's about 11,000 CPU-hours to find one etcd bug. Nobody publishes the cost of building the harness itself.
10. What "enough" simulation looks like. No source gives a falsifiable threshold for when a simulation suite has covered enough schedules; the closest is FDB's conditional coverage counters and the TigerBeetle blind-spot post, which argue that a quiet fuzzer is not evidence of absence.
11. Which specific bugs ox's own known failures (a swallowed Cancelled, a finalizer suspending while cancelled, a stdlib mutex held across a suspension, a shared I/O buffer, a lost wake-up, a keepalive flood dying at 11 minutes, half frames) would have been caught by which mechanism. That mapping needs the other slots' analyses; I only note where a mechanism plausibly reaches (items 2.1, 2.3, 2.4, 2.8) and I have not tested any of it.
12. Antithesis's internals beyond what they chose to publish: the hypervisor post says "I've also left out one key design pillar ... all the functionality that allows efficient state exploration and time-travel debugging. (We are not replaying every single execution path from the beginning – we would not waste your time like that!)". So its exploration strategy is not fully public and I do not infer it.
13. The full content of the Will Wilson talk. The crawl returned a partial transcript (about 42 KB of text); every quote I use from it appears verbatim in the retrieved text, and I make no claim about portions I did not retrieve.
14. Whether miou or affect offer any deterministic-testing support. I read miou's scheduler tutorial (a teaching document, with no determinism or seeding claim) and I downloaded but did not analyse affect; I found no seed or determinism support in miou's library sources by grep, and I have no finding about affect.

---

## Summary

The subject of this slot is how to make deterministic, seeded simulation the default for concurrency and protocol tests in OCaml, and the finding is that OCaml is closer to it than it looks and further from it than it should be.

Closer, because the two hard preconditions already hold. Eio documents a real guarantee — "Within a domain, fibers are scheduled deterministically", and programs are nondeterministic only if handed a capability that makes them so — and Eio_mock.Backend.run_full already is a deterministic, single-threaded event loop with a virtual clock, no OS calls, and deadlock detection instead of hangs. The public provider API (Eio.Private.Effects) is exactly three effects, and Eio contains two complete schedulers written against them: the mock backend (116 lines) and the fake scheduler (21 lines) used by its own dscheck tests. Effect handlers do make a deterministic scheduler feasible; that is demonstrated in-tree, not hypothesized.

Further away, because everything FDB would call buggification, swarm testing and workload generation is missing, and the seed never reaches the schedule. The OCaml ecosystem's current answer to concurrency testing is repetition at the level of qcheck-lin and qcheck-stm, whose own documentation says CPU scheduling and GC "may hinder reproducibility", amplified by a Gc.Memprof hack to switch contexts more often. dscheck is a genuine model checker, but only for lock-free Atomic-based code, and Eio itself keeps it behind a non-default alias with a performance caveat. Crowbar and AFL cover parsers. Eio's own tests are golden traces. What is absent is the middle: a seeded harness that runs the system single-threaded with fake time, fake I/O and seeded faults, prints a replayable seed, and checks its own determinism.

The external evidence is consistent about what such a harness must have, and the mission's list matches it, with one correction worth carrying: "fault injection at every suspension point" is not how any of these systems is described. FDB injects at explicit buggify sites (25% of runs activate a site, 25% of calls fire it) and at modelled network and disk operations; TigerBeetle rolls dice every tick; madsim additionally randomizes every scheduling decision by making the ready queue first-in-random-out; Antithesis injects at I/O exchange points and through the guest scheduler. The two mechanisms that generalize to Eio are seeded per-operation decisions in the mocks and a seeded queue discipline in a test-only scheduler.

Two more lessons from the sources shape the recommendation list. First, the seed is a first-class input: FDB, TigerBeetle, Dropbox, Resonate, SlateDB and madsim all treat "seed plus commit" as the reproducer, and FDB and Dropbox both spend a small fraction of runs checking that the same seed really does produce the same execution. Second, a quiet simulator proves nothing: TigerBeetle published the bug its own VOPR missed (a query-intersection bug hidden by a workload that had accidentally made probing unnecessary), and Antithesis's etcd case shows the opposite lever, raising the frequency of the two faults that mattered until a bug that appeared once per 11,000 CPU-hours appeared about twenty times more often. A coverage counter that fails the nightly when a fault class never fired is the cheap defence against the first, and a replayable per-decision log with per-class fault control is what makes the second possible.

For ox specifically, the local evidence is encouraging: test/stress already runs real Eio fibers on Eio_mock's virtual clock, stress_support already prints and accepts a seed, the dune rules already parameterize on OX_STRESS_SEED, and lib/test has a fiber census that can serve as an oracle. The ranked list in section 2 therefore starts with the harness and the determinism self-check, moves the seed into the mocks and the faults, makes the capability-to-fake mapping a compile-time obligation, and leaves the most powerful item — a seeded first-in-random-out scheduler over Eio.Private.Effects — for last, test-only and gated.

Report: /tmp/eio-hardening/03-simulation/REPORT.md
