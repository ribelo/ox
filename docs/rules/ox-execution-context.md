# ox-execution-context

This bounded audit covers two concrete wrong-context failures: native callbacks
performing known Eio operations, and Eio callbacks performing known synchronous
waits. The default gate leaves it dormant; explicit `--rules ox-execution-context`
runs an audit, not consumer activation.

Fully applied compiler-authenticated Ox_blocking entries execute their unlabelled
callback natively. Known Eio Fiber/Switch operations there are findings: for
example, Eio.Fiber.yield needs a fiber context absent from a native worker.
Caller-side cancellation/release hooks stay on the owner. Returned/stored closures
and dormant partial applications are not executed. ^safe-sr6e ^safe-9hbm ^safe-eftp

Known Eio_main/Linux/Posix and Ox_test roots establish owner execution. Unix
sleep/read/write, Thread delay/join, Domain.join and native Counting acquisition
there can stall every sibling fiber. Reads/writes require a proven blocking
descriptor; nonblocking descriptors and actual native jobs stay legal. Descriptor
escape, unresolved callback transfer and candidate-bearing analysis horizons are
named undecided, not certified. ^safe-9ved ^safe-r5ye ^safe-ohen

Local aliases/closures/helpers are bounded to 512 expressions and 32 active calls.
Known Eio candidates escaping opaque helpers, or present in invoked unsupported
optional defaults, remain undecided. Ordinary opaque code without a selected
candidate is outside the catalogue; absence of diagnostics proves neither NoEio
nor whole-program context safety. Compiler UIDs, imported CMI fingerprints and
authored source freshness remain required.

Native controls compile interfaces first and assert literal physical sites,
categories and complete messages, retaining duplicates. Counting owner/native
sibling-progress controls reproduce the failure. Installed/no-Git consumer probes
verify the combined public status 0/1/2 boundary, not native purity or lease safety.
