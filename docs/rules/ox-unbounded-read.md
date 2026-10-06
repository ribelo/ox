# ox-unbounded-read

Whole-stream acquisitions need a finite budget, not a compiler-valid max_int.
The typed visitor compares compiler value UIDs; opens, module aliases and local
value aliases do not change the operation. Shadow modules are unrelated.

It checks Eio.Flow.read_all (including raw HTTP body flows), unbounded
Eio.Buf_read.of_flow, and take_all passed to Process.parse_out or an unbounded
Buf_read.parse/parse_exn. Finite max_size readers and parsers are accepted.
Where installed, Cohttp_eio/Piaf Body.to_string identities are also sinks;
Ox HTTP bounded body APIs are not sinks. of_flow already requires max_size
by its type; omitted arguments are not a newly discovered production bug.

Opaque reader/HOF provenance is undecided, not a demonstrated unbounded read.
This is local budget evidence, not whole-program allocation analysis.

Contract: [unbounded-read spec](../issues/ox-safety-gate/20-unbounded-read.md).
