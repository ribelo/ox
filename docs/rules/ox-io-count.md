# ox-io-count

Reports disposal of a supported operation's transferred-byte count. Binding it to
an unused name (including an underscore-prefixed name) does not handle short I/O.
This is a demonstrated disposal finding, not a proof that every retained count is
used correctly. (^safe-jwwj, ^safe-qmcw, ^safe-t50j, ^safe-fr73)

## Operation contracts

| Resolved operation | Result | Repair semantics |
| --- | --- | --- |
| Unix.read, Unix.write, Unix.single_write | int | For streams, handle partial progress, EOF and zero progress; preserve message semantics on message descriptors |
| Stdlib.input | int | Stream progress and EOF |
| Unix.recv, Unix.send | int | The socket type is not inferred: distinguish streams from datagrams |
| Unix.recvfrom | int * Unix.sockaddr | Track the count, not just the retained address; preserve one-message semantics |
| Unix.sendto | int | Preserve one-message semantics |

The table uses compiler-resolved identities and checks the inferred result shape,
not source spellings. A pure compilation unit need not depend on Unix. Actual
imports are verified by the artifact engine; when Unix is available, every listed
Unix contract is required. Missing imported compiler evidence is an error, not a
clean decision. Module aliases and
opens normalize to the original operation. Shadowed Unix/Stdlib modules, local
lookalike functions and arbitrary integers are not classified by name.

## Wrong

```ocaml
let save fd bytes = ignore (Unix.write fd bytes 0 (Bytes.length bytes))
let receive fd bytes =
  let _count, address = Unix.recvfrom fd bytes 0 (Bytes.length bytes) [] in
  address
```

## Right

For a stream, select the existing Eio complete-transfer operation where its
contract fits: Eio.Flow.write writes all buffers; Eio.Flow.read_exact fills a
buffer or raises End_of_file; Eio.Flow.copy copies until EOF. Empty exact reads
are complete without touching the provider. Preserve the existing operation's
exceptions/error channel and cancellation behavior. Do not invent a second I/O
framework merely to replace a call. (^safe-fr73, ^safe-qmcw)

```ocaml
let save sink buffers = Eio.Flow.write sink buffers
let read_exact source buffer = Eio.Flow.read_exact source buffer
let read_once fd bytes = Unix.read fd bytes 0 (Bytes.length bytes)
let receive fd bytes =
  let count, address = Unix.recvfrom fd bytes 0 (Bytes.length bytes) [] in
  count, address
```

Returning the count delegates the obligation; keeping a datagram's length allows
processing exactly this message and considering truncation. Do not apply a stream
loop-until-full repair to a datagram: it may combine or split messages. recv/send
alone do not prove the socket type, and descriptor read/write can also carry
messages. The diagnostic keeps that distinction explicit. (^safe-t50j)

## Finite detection horizon

- Direct fully applied supported operations in Stdlib.ignore (or a proven local
  alias), wildcard bindings, and unused local named bindings are detected.
- For recvfrom tuple patterns only the first component matters; an unused count
  is a finding even if the address is used. Literal/refutable count patterns
  inspect the count and are not treated as disposal. Returning/using the whole tuple is
  legitimate delegation. Uses are matched by compiler identifier, not name.
- Local value aliases preserve operation contracts. A local forwarding function
  is proved only when its body is one fully applied known operation (or already
  proved wrapper) and each forwarded argument is one of its parameters. An extra
  unused capability parameter is allowed. Compiler value identities also support
  these definitions reached through local modules and module aliases.
- Known local count-result bindings and direct immutable aliases retain provenance
  through resolved ignore and wildcard disposal. The finding points to the original
  transfer. A genuine use alongside disposal keeps the count clean; retaining it is
  not proof of correct handling. Compiler identifiers distinguish shadowed bindings.
- Unknown wrappers, separately compiled wrapper bodies, optional/default-argument
  elaboration, branches, arithmetic on the result, and heap/opaque/general data-flow
  are not analyzed. Partial applications are not transfers.
- The check does not prove a loop terminates, classify a descriptor/socket's
  transport, prove sufficient buffer sizes, or validate truncation handling.
  Missing/stale/unreadable/partial typed artifacts remain engine evidence errors.

The real [Ox_test write loop](<../../lib/test/ox_test.ml#L308-L320>) consumes each
Unix.write result and stays clean. The corpus has no discarded count requiring a
new production wrapper. It does not have an explicit zero-progress guard; retaining
a count alone is not a transfer-correctness proof.

## Regression seams

The [decider tests](<../../test/lint/safety_io_count/test_io_count.ml>) compare exact
finding locations and semantic categories against compile-only
[violating](<../../test/lint/violating/io_count.ml>) and
[clean](<../../test/lint/clean/io_count.ml>) fixtures, and check the actual Ox_test
annotation. Generated intentionally invalid/unknown fixture programs compile in a
[declared nested project](<../../test/lint/safety_io_count/fixtures/dune-project>);
the assertion harness remains in the parent project, without directory exemptions.
[Transfer regressions](<../../test/lint/safety_io_count/test_transfer.ml>)
exercise existing Eio public complete-transfer seams with scripted bounded short
reads/writes, premature EOF, and unchanged exception identity after partial progress.

The pinned Eio source rejects a zero read by assertion (zero is not EOF in its
provider contract). Its write seam retries zero without a guard; the test bounds
that invalid-provider fault to zero followed by an unchanged exception. It does
not claim that Eio protects against a provider returning zero forever. No production
provider or wrapper is added. (^safe-qmcw, ^safe-t50j)

## Check

```sh
nix develop -c dune build @test/lint/safety_io_count/runtest
# After shared registry/install integration:
ox-lint --require-typed --rules ox-io-count path/to/source.ml
bash test/lint/safety_io_count/check-cli.sh /absolute/installed/prefix
```

Findings use exit 1; missing evidence or an unknown rule uses exit 2. The
[installed acceptance script](<../../test/lint/safety_io_count/check-cli.sh>) uses
only the explicit installed executable and share fixtures, compiles a consumer in
a fresh directory outside the checkout, and invokes --self-check and both fixture
checks there. The optional io-count-cli alias is not part of runtest until shared
registry and installed assets are integrated. (^safe-y047, ^safe-czoe, ^safe-tlyw)
