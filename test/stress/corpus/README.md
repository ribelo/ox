# Parser seeds — ^nstress-ln4z

HTTP fixtures are complete valid wire messages with CRLF line endings. WebSocket
fixtures are complete valid RFC 6455 frames in whitespace-separated hexadecimal;
`masked-text.hex` is the masked client frame, all others are unmasked server frames.
`continuation.hex` is valid at the frame-codec boundary (fragment sequencing belongs
to the connection). `binary-126.hex` exercises the extended 16-bit length.

The executable validates every fixture, tries every shorter byte prefix, then
mutates these seeds with bounded QCheck2 generators and integrated shrinking. It
also checks decimal/hexadecimal integer overflow, configured HTTP limits, and
WebSocket 16/64-bit length boundaries. A bounded port of
`v1:test/http_fuzz/fuzz_h1_write.ml` checks byte-buffer/string/buffer request writers
agree or reject together, rejected output is unchanged, and valid generated
requests round-trip through the loopback parser with their exact method, target
and body. Current H1 writers are request-only; H1_parse parses the server's
responses, not serialized requests. No response/flow writer API is invented.
Mutated/arbitrary inputs are bounded at 8192 bytes; deterministic valid payload
probes additionally cover 65536 bytes. Claimed lengths can exceed these bounds
without allocating their claimed payloads.

Crowbar was requested but is absent from the existing switch; QCheck2
is used without installing dependencies or running AFL. The request parser is
private, so it is tested through one loopback HTTP server, including typed body
errors and bounded HTTP rejection responses. Premature EOF before a complete
request head may legitimately close without a response.

When running the executable from the repository root, pass
`--corpus test/stress/corpus`. Dune's
`@stress` action runs from `test/stress` and uses the default `corpus` directory.
Default seed: 6060. `--seed` and `OX_STRESS_SEED` follow `Stress_support`.
