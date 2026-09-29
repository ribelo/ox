# Posix wake-up stress (^nwake-fz0j)

The Door executable runs the unchanged child loop from Pie's plain-Eio
reproducer: 1,000 sequential `Eio.Process.run` calls executing
`/bin/sh -c "exit 0"`. There are no operation-level Eio deadlines or Ox_process
wrappers. Each **process** is bounded by `timeout --kill-after=1 5`; the OS timer
still fires if the Eio scheduler stalls. The separate stress aliases are not
part of `runtest`. Zero disables the tick; the default enabled interval is 50 ms.

## Commands

From the Ox root, using the task's dedicated foreground build directory:

```sh
timeout 900 nix develop -c env DUNE_BUILD_DIR=_build_r55 dune build \
  @test/stress-posix-wakeup/stress-posix-wakeup
timeout 900 nix develop -c env DUNE_BUILD_DIR=_build_r55 dune build \
  @test/stress-posix-wakeup/stress-posix-wakeup-disabled
```

For diagnostic comparisons, build `test/stress-posix-wakeup/plain.exe` and run
`stress.sh` with its absolute executable path, 50 runs and interval 0.
`plain.ml` is the unchanged standalone control, with only an `eio_main`
library dependency; the interval environment variable has no effect on it.
Standalone shell runs write the last child's output to `stress.log` in their
working directory. Run them from this directory to keep that scratch output local.

## Results, 2026-09-29 (Europe/Warsaw)

All populations used the installed Eio posix backend, 1,000 children per process,
50 processes per population and the same 5-second OS bound. No strace, debugger,
native wrapper, dependency patch or installed-library modification was used.
All counts below have **zero other failures**.

| Program and interval | Conditions | Passed | OS timeouts |
| --- | --- | ---: | ---: |
| Door, 50 ms | Initial pair of Dune aliases (both populations ran together) | 50/50 | 0 |
| Door, disabled | Initial pair of Dune aliases (both populations ran together) | 50/50 | 0 |
| Door, disabled | Sequential, untraced, no added load | 50/50 | 0 |
| Door, disabled | Parent/children pinned to CPUs 0-1; one bounded `yes` on CPU 0 | 50/50 | 0 |
| Door, 50 ms | Same CPU affinity and bounded load | 50/50 | 0 |
| Plain Eio, no tick | Sequential, untraced, no added load | **47/50** | **3** |
| Door, 50 ms | Sequential, untraced, no added load, after the plain control | **50/50** | **0** |

The load experiment used `taskset -c 0,1` for the runner and one
`taskset -c 0 timeout --kill-after=1 350 yes >/dev/null` process, killed and
waited for when the batch ended. Each batch itself had a 360-second OS bound.
No load process was left running.

**Evidence limit:** the Door-hosted stress did not reproduce a hang with its
mitigation disabled, even sequentially or under the tested contention. Its
additional topology/code layout can change signal timing, but the specific
reason was not established. Therefore the Door comparison alone does not prove
a causal fix. The unchanged plain-Eio control carries the current “fails without”
evidence; the Door's enabled runs show bounded completion under those same
ambient conditions. Pie's separately recorded prepared-text comparison carries
the consumer “fixed with” evidence. The three plain-Eio timeouts were counted
as OS timeouts, not individually traced to confirm their kernel wait state.
A passing disabled population does not imply the dependency race is repaired.

The normal app regression additionally sends a real SIGTERM and runs cleanup
inside `Eio.Cancel.protect`: an Eio process release hook kills and reaps a child,
then 1,000 immediately exiting raw-Eio children are reaped before the Door exits
zero. Its child runtime has a 5-second external bound. Deterministic mock-clock
tests check posix cadence, zero/linux gating, log selection and timer removal
when the outer switch ends; production fixture tests check option/env precedence,
service-only journal logging and its level filter, plus owned-command empty stderr
with the 50 ms ticker enabled.
