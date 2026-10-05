# ox-constant-index

Rejects a proved out-of-bounds constant read through the compiler-resolved
standard `Array.get`, `String.get` or `Bytes.get`. This is a demonstrated defect,
not a policy restriction: executing the read raises an indexing exception rather
than returning a typed result error. The diagnostic states the actual index,
length and half-open bounds. (^safe-rxya, ^safe-d197, ^safe-xd2e, ^safe-czoe)

## Wrong

```ocaml
let read () = "\x41\n".[2] (* two decoded bytes; valid indexes are 0 and 1 *)
```

## Right

Correct the constant, or explicitly check an input index and preserve expected
failure as a result. Catching all exceptions does not turn a defect into a result
contract.

```ocaml
let read () = "\x41\n".[1]
let get a i =
  if i >= 0 && i < Array.length a then Ok (Array.get a i)
  else Error `Index_out_of_bounds
```

## Finite detection horizon

- Typed literal arrays and decoded string literals have known lengths. Strings
  are counted in bytes, not source characters: `"é"` has two UTF-8 bytes.
- Bytes are supported only when constructed by resolved `Stdlib.Bytes.of_string`
  from a supported literal string. Arbitrary bytes producers are not inferred.
- Indexes are typed integer constants, including negative literals. Zero-length
  collections, -1, the last valid index and the exact upper bound are handled.
- Direct local variable bindings and chains of local value aliases are followed
  by compiler identity. Module aliases and opens use normalized compiler paths.
  Ordinary `.( )` / `.[ ]` syntax is covered only when typing resolves it to one
  of these getters; source spelling is never evidence.
- Function parameters, arithmetic or branching ranges, arbitrary wrappers,
  collection factories, partial getter applications, unsafe getters, writes and
  exported value aliases across module boundaries are outside this slice.
  There is no whole-program range solver. No finding at an unknown-length site
  is not a proof that its runtime read is safe. (^safe-xd2e, ^safe-tlyw)

A user-defined module called `Array` with a total `get`, or a same-named local
function, is a legitimate counterexample. A user-defined `Bytes.of_string` can
return a different-sized buffer and is not treated as a standard bytes origin.

## Evidence and checks

Build fresh annotations first, then use the matching installed decider:

```sh
dune build @install
ox-lint --require-typed --rules ox-constant-index lib/
```

Findings exit 1. Missing, stale, partial or mismatched annotations and missing or
changed imported interfaces exit 2; they cannot become clean or be waived with
a comment. The visitor requires filesystem-read authority for compiler evidence
and never mints a capability. (^safe-fr73, ^safe-y047, ^safe-m5sp)

The [violating](<../../test/lint/violating/constant_index.ml>) and
[clean](<../../test/lint/clean/constant_index.ml>) fixtures are installed assets.
The [typed decider test](<../../test/lint/safety_constant_index/test_constant_index.ml>)
asserts exact fixture sites and decoded numeric bounds without executing defective
fixture functions. Run `dune build @test/lint/safety_constant_index/runtest`.
After registration, `dune build @test/lint/safety_constant_index/cli` exercises CLI
findings, legitimate counterexamples and evidence failures. The
[CLI script](<../../test/lint/safety_constant_index/check_cli.sh>) also accepts an
installed binary plus the installed clean and violating fixture paths.
(^safe-t37w, ^safe-12o2)
