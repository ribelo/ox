---
status: ready-for-agent
package: eta_test
consumer: Leash milestone 4 (hand-phof), recorded as Leash etagap-43zf
---

# The fake process manager scripts a child's output

## Problem Statement

`Eta_test.Process` scripts a child's exit and records its argv, env and descriptors, but a child's standard output and error cannot be scripted. Leash's handoff runs `notify-send --action done=Done` and resumes the tab when the child prints `done`; to test that path it had to write its own scripted runner beside eta_test's fake manager (etagap-43zf), so the code under test does not go through `Eta_process.Child` in that test.

## Solution

Scripts carry output: a child may write chunks to stdout/stderr, optionally after a delay on the test clock, before exiting or blocking.

## User Stories

1. As a test author, I want an `Eta_test.Process` script to write given chunks to the child's stdout and stderr (delivered through the pipes `Eta_process.Child` exposes with `~stdout:Pipe`/`~stderr:Pipe`) and then exit with a scripted status or block until signalled, so that code reading a child's output is tested through the real Child path. ^ntest-f2rm
2. As a test author, I want an output chunk to be deliverable after a delay on the mock clock (or on cue from the test), so that "the human clicks Done after a while" and "the child is stopped before it prints" are both expressible. ^ntest-8v5z

## Implementation Decisions

- Additive: existing `Exit` / `Block_until_signal` scripts keep their meaning; output is a new script form or an optional field, whichever reads better in `eta_test.mli`.
- Output goes through real Eio pipes so the consumer reads it exactly as from a real child; EOF follows the last chunk when the child exits, and on signal-termination.
- The fake still records argv/env/cwd/fds as today.

## Testing Decisions

- `test/test`: a scripted child printing lines read through `Eta_process.Child` stdout; a delayed chunk on the mock clock; a child stopped before its delayed chunk — its reader sees EOF, not the chunk.

## Out of Scope

Scripting stdin reads.
