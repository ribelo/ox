# OxCaml Typedtree feasibility spike
**typed tier: feasible with conditions**
Compiled and ran the discarded-result rule on pinned **5.4.0+ox**: **113 implementations, 53,238 expressions, 40 discard candidates, 8 result-typed findings, zero failures**.

The decisive rule is established, not merely AST access. Conditions: exact compiler pin; complete, fresh annotations and dependency CMIs; per-compilation-unit load paths/environment reconstruction; documented limits on value aliases and interprocedural reasoning. This is a throwaway experiment for [^nlint-hxar](</home/ribelo/projects/ribelo/ocaml/ox/docs/issues/ox-lint/01-ox-lint.md#L23>), not a landed linter or a proof of the suspension-closure rules. Repository sources were not edited; the permitted install build was run. All experiment writes are under this directory; an independent helper owns the interface/mode directory.

## 1. Can Cmt_format read usable implementation structures across libraries?

**Yes for every discovered library CMT in this build.** [metadata.tsv](</tmp/ox-lint-spike/metadata.tsv>) records successful Cmt_format.read_cmt calls for all **113** paths in [cmt-list.txt](</tmp/ox-lint-spike/cmt-list.txt>). Every payload is **Implementation**: no Interface, Packed, partial-implementation, or failed-read payloads. Traversal subsequently succeeds on all 113, proving that the structures are usable, not just their headers.

The compiled [metadata reader](</tmp/ox-lint-spike/metadata.ml>) prints compiler **5.4.0+ox**, CMT magic **Caml1999T581**, and CMI magic **Caml1999I581**.

| Directory under lib | CMTs |
|---|---:|
| ai / ai_chat / ai_openrouter | 5 / 5 / 6 |
| ai_realtime / ai_systemone / app | 3 / 5 / 5 |
| blocking / caps / caps/door | 1 / 5 / 1 |
| http / ipc / json | 24 / 2 / 1 |
| observability / otel / ox | 4 / 5 / 18 |
| ppx_yojson_minimal / process / rpc | 2 / 3 / 2 |
| sql / sql_dsl / test | 10 / 5 / 1 |
| **Total** | **113** |

Coverage is not “113 original source files.” [coverage.json](</tmp/ox-lint-spike/coverage.json>) reconciles annotations with [97 original ML paths](</tmp/ox-lint-spike/ml-list.txt>): **96** are represented, plus **17 Dune-generated wrapper/alias implementations**. Fifteen annotations name preprocessed sources; their locations still point into original source.

The absent ML annotation is [the PPX executable main](</home/ribelo/projects/ribelo/ocaml/ox/lib/ppx_yojson_minimal/main.ml>). Its existing native compilation [Dune rule](</tmp/ox-lint-spike/main-rule.sexp#L45-L71>) omits -bin-annot. Its interface annotation exists but its implementation CMT does not. This is an executable-coverage gap, not a failed library read. A production gate must inventory expected modules and explicitly depend on their annotation targets: “glob whatever exists” can silently miss native-only executables.

Recorded byte compilation commands include -bin-annot, -bin-annot-occurrences and -bin-annot-cms. No library-specific payload incompatibility appeared. This was an existing warm repository build, not a clean rebuild. A separate fresh scratch install build also produced a readable library CMT; see question 7.

## 2. Do interfaces preserve val types and attached docstrings?

**Reachable, established by the independent compiled interface probe.** Its [report](</tmp/ox-lint-spike-interfaces/REPORT.md#L42-L119>) compares every original source signature against its typed artifact: **97 interfaces / 97 CMTIs**, **1,301 vals / 1,301 typed val declarations**, no missing/extra declarations, no full-span mismatches, and nonempty printed types for every val. All **488 attached-doc sets** agree in text and span; both typed attribute locations retain the same docs. The final reproduction script exits 0.

Cmt_format.read_cmt reads CMTI too: dispatch on Interface, then traverse Tast_iterator.signature. Typedtree.value_description exposes val_name, val_loc, val_desc.ctyp_type, val_attributes and val_val.val_attributes. The ocaml.doc payload is an attached string expression in the attribute. Nested signatures are covered. See the helper's [coverage summary](</tmp/ox-lint-spike-interfaces/coverage-summary.json>) and exact [run script](</tmp/ox-lint-spike-interfaces/run.sh>).

**Limits:** 813 vals have no attached doc; this is not automatically 813 behavior-policy violations because module-level defaults/inheritance are a rule-design decision. Availability does not prove prose truth, cancellation behavior or suspension safety. Fifteen artifacts hash preprocessed interfaces rather than all original/preprocessor inputs; Dune freshness remains necessary. Floating ocaml.text and inherited module docs are outside this attachment comparison.

## 3. Does Tast_iterator traverse expressions and recognize real result types?

**Yes.** [spike.ml](</tmp/ox-lint-spike/spike.ml>) extends Tast_iterator.default_iterator, calls the base traversal after each callback, and visits **53,238 expressions** across the 113 structures. The final run classifies **3,039 expression nodes** as result; this telemetry is not the candidate count or an interprocedural fact. See [corpus.log](</tmp/ox-lint-spike/corpus.log>) and [corpus.tsv](</tmp/ox-lint-spike/corpus.tsv>).

Classification takes exp_type in the expression's reconstructed exp_env, expands manifest aliases with Ctype.expand_head, inspects Types.get_desc, requires Tconstr(path, [success; error], _), normalizes the type path, then compares with the canonical stdlib result path using **Path.same**. Printed type names are only diagnostic text. The canonical target is looked up in the **initial environment**, not the lexical environment: a local module called Stdlib cannot redefine what “really result” means.

The compiled [boundary fixture](</tmp/ox-lint-spike/fixture.ml>) and [output](</tmp/ox-lint-spike/fixture.tsv>) prove:

- Direct result and bare wildcard result bindings are reported.
- A manifest outcome = result alias is reported despite its different raw type head.
- An unrelated result type, including under a shadowing Stdlib module, is clean.
- Integers, booleans, and a fully handled match are clean.
- A local function named ignore is not mistaken for Stdlib.ignore.
- Stdlib module aliases and opens work. The compiler elaborates the tested @@ and |> forms into the real ignore call, and these are reported too.

The stored environments are summaries. The probe reconstructs them with Envaux.env_of_only_summary ~allow_missing_modules:false, resets caches, and initializes each annotation's visible/hidden load paths. Dune records the remapped **/workspace_root** as cmt_builddir, which does not exist here; relative include paths must be rebased onto the actual _build/default. This plumbing is essential.

A still-polymorphic node whose inferred type is a variable is not established to be result. The corpus wildcard RHS has type 'a and is not reported. Runtime instantiation, abstract representation and interprocedural specialization are not inferred by this classifier.

## 4. Can calls and exception constructors be identified after aliases/open?

**Yes for compiler-resolved module aliases/open. Same-unit exception rebinding also has usable origin metadata.** Calls expose Texp_ident.path. Env.normalize_value_path plus Path.same identifies the actual declaration, independently of source spelling or final name component.

Selected evidence from [fixture.tsv](</tmp/ox-lint-spike/fixture.tsv#L15-L20>):

| Written form | Canonical outcome |
|---|---|
| fork after opening F, where F aliases Eio.Fiber | Eio__core.Fiber.fork; Eio fork **true** |
| F.fork through module aliases | Eio__core.Fiber.fork; Eio fork **true** |
| a local fork | stamped local identifier; Eio fork **false** |
| Cancelled after opening an alias of Eio.Cancel | Eio__core.Cancel.Cancelled; cancellation **true** |
| Stopped rebound from C.Cancelled | local extension path; rebinding graph reaches cancellation origin **true** |

Patterns expose Tpat_construct and a constructor description whose cstr_tag is Types.Extension path. Normalization identifies real cancellation patterns in [blocking](</home/ribelo/projects/ribelo/ocaml/ox/lib/blocking/ox_blocking.ml#L169>) and [the child watcher](</home/ribelo/projects/ribelo/ocaml/ox/lib/process/child.ml#L134-L135>). Public spelling and internal canonical paths differ.

A measured caveat: exception rebinding gives a different constructor UID, so **UID equality alone misses this alias**. The prototype records Text_rebind(origin_path, _) under the stamped extension identifier and follows the origin for the same-unit fixture. Cross-unit exported exception rebindings, nested-module rebindings, functors, first-class modules, value aliases of fork, and higher-order calls are **not established**. Module-path normalization is not a whole-program call graph.

Optional Eio path telemetry looks up the target only when Eio's CMI is on that unit's load path; unrelated units such as the PPX do not require Eio. The discarded-result rule itself does not require Eio.

## 5. What OxCaml mode information survives?

**Inspectable, established by the independent compiled mode probe.** The [helper report](</tmp/ox-lint-spike-interfaces/REPORT.md#L120-L166>) parses and reads all six requested source/artifact pairs: [duration](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/duration.mli>), [cause](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/cause.mli>), [resource](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/resource.mli>), [scope](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/scope.mli>), [SQLite](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/sqlite.ml>) and [SQL DSL](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql_dsl/ox_sql_dsl.ml>). The ordinary pinned parser handles the syntax. Fresh local/global/default/unique/portable controls compile and retain the expected distinctions.

Reachable information includes explicit located mode/modality atoms; typed arrows' effective constant modes and written annotations; function parameters' fp_mode and solver bounds; Texp_mode in exp_extra; effective val modalities including inherited portable defaults; record-field modalities; written and semantic type kinds. Record fields are reached through typ_kind because this Tast_iterator has no label-declaration callback. See [mode evidence](</tmp/ox-lint-spike-interfaces/modes-summary.stdout>) and the helper's [fresh control](</tmp/ox-lint-spike-interfaces/fixture.jsonl>).

**Important limit:** an unannotated implementation parameter can retain a global..local locality interval even when its exported signature argument is global. Empty written annotations are not proof of an effective global mode, and fp_mode is not always a constant. Explicit spelling, inherited/default effective mode and inferred bounds are different questions; source parsing is still useful for attribution. This establishes inspectability, not a complete semantic query layer for every mode axis or a suspension rule.

## 6. Does the actual discarded-result rule work end to end?

**Yes: eight concrete result-typed discards, not 39/40 name-based guesses.** The rule checks the actual argument of a call whose resolved identity is Stdlib.ignore, or the RHS of a bare wildcard value binding. There is no function-name suffix test or list of result-returning Ox functions.

The final [assertion run](</tmp/ox-lint-spike/check.log>) confirms **39 ignore candidates + 1 wildcard = 40**, **8 findings**, **32 clean candidates**, **0 failures**. All eight findings are ignore calls:

| Site | Discarded expression | Inferred type |
|---|---|---|
| [ws_client:426](</home/ribelo/projects/ribelo/ocaml/ox/lib/http/ws_client.ml#L426>) | close ~code ~reason t | (unit, error) result |
| [ox_otel:426](</home/ribelo/projects/ribelo/ocaml/ox/lib/otel/ox_otel.ml#L426>) | finish t, release callback | (unit, error) result |
| [ox_otel:455](</home/ribelo/projects/ribelo/ocaml/ox/lib/otel/ox_otel.ml#L455>) | finish t, shutdown fallback | (unit, error) result |
| [child:134](</home/ribelo/projects/ribelo/ocaml/ox/lib/process/child.ml#L134>) | Eio.Promise.await finished | (exit, exn) result |
| [pool:28](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/pool.ml#L28>) | Connection.close c | (unit, sql_error) result |
| [pool:57](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/pool.ml#L57>) | Connection.close c | (unit, sql_error) result |
| [pool:73](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/pool.ml#L73>) | shutdown_state s | (unit, 'a) result |
| [pool:105](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/pool.ml#L105>) | Connection.close c | (unit, sql_error) result |

Actual diagnostic (columns are zero-based in this throwaway tool):

~~~text
lib/http/ws_client.ml:426:10: ox-lint-discard-result: ignore discards (unit, error) result; match Ok/Error or propagate the error
~~~

Clean candidates include signal_behavior, ints, bools, inet_addr, options, Sqlite.rc, exit values, Ox.Exit.t, and the unconstrained wildcard RHS. In particular, [child's other cleanup](</home/ribelo/projects/ribelo/ocaml/ox/lib/process/child.ml#L139>) discards an **exit**, not result; [supervisor cleanups](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/supervisor.ml#L344-L349>) discard **Ox.Exit.t**, not result. A lexical census cannot make these distinctions.

The old [row 66 statement](</home/ribelo/projects/ribelo/ocaml/ox/docs/issues/raw-concurrency-gate/01-raw-concurrency-gate.md#L11>) cites **39** sites. This sampled tree has **40** AST candidates; one is in the build-time [deriver](</home/ribelo/projects/ribelo/ocaml/ox/lib/ppx_yojson_minimal/derive.ml#L676>) and discards bool. Excluding it leaves 39, but the earlier prose does not define that exclusion or an immutable revision. This report does **not** assert this as the historical cause. The current candidate inventory is preserved; only eight are result-typed.

**False positives:** none found for the stated type-and-syntax predicate in the examined corpus/fixtures. Intentional best-effort cleanup still discards a result; policy needs a named discard/waiver with a reason, not a weaker type test. The eight findings are not evidence of eight runtime bugs.

**False negatives/boundaries:** compiled fixtures deliberately miss a value alias of ignore (drop result) and a higher-order callback invoking a passed ignore. Resolving these requires additional value/dataflow reasoning. General unused bindings, destructuring, arbitrary sequencing and consumption within callbacks are outside this narrow rule. An unconstrained type or abstract representation is not treated as proof of result. Cancellation safety, correct error propagation and transitive suspension closure are not claimed.

## 7. Build/run orchestration, missing/stale annotations, and wall time

Build with **the same pinned compiler and compiler-libs** as the inspected modules. Build annotations first and run in the matching build context; a compiler-libs package name is not an ABI guarantee.

A fresh [scratch Dune project](</tmp/ox-lint-spike/dune-probe/dune-project>) contains a library and compiler-libs.common driver. Its [lint alias](</tmp/ox-lint-spike/dune-probe/dune>) explicitly depends on the CMT/CMTI. A fresh install build succeeded; running the alias compiled the driver and failed on the intended violation with **one finding, zero reader failures**, recorded in [dune-lint.log](</tmp/ox-lint-spike/dune-lint.log>). This proves basic Dune orchestration, not a production integration into ox.

Production requirements:

1. Derive a manifest from expected modules, including native-only executables, and depend on every annotation target—not a glob of whatever already exists.
2. Reconstruct per-file summarized environments and visible/hidden load paths against the real build context, not the remapped cmt_builddir or arbitrary consumer working directory.
3. Required mode fails on absent, unreadable, incompatible or partial artifacts, naming the file. Optional mode may warn/skip as specified, but must not silently pass the typed rule.
4. Source/preprocessor inputs **and imported CMI dependencies** belong in the build graph. Successful deserialization is not proof of freshness.

Measured failures:

- [noannot.ml](</tmp/ox-lint-spike/noannot.ml>) compiled without -bin-annot has no CMT. [missing.tsv](</tmp/ox-lint-spike/missing.tsv>) records missing-file failure and rejection of a CMI passed as a CMT.
- [stale.ml](</tmp/ox-lint-spike/stale.ml>) was compiled with a violation, then fixed **without rebuilding**. Cmt_format still reads the old CMT. The prototype's source-digest check rejects it with exit 2 ([stale.log](</tmp/ox-lint-spike/stale.log>)); bypassing the check emits the obsolete violation ([stale-unsafe.stdout](</tmp/ox-lint-spike/stale-unsafe.stdout>)).
- A deliberately modified CMT magic header is rejected with exit 2 ([wrong-magic.log](</tmp/ox-lint-spike/wrong-magic.log>)). This is a simulated incompatible header, not an actual cross-version migration test.

The digest helper is only a partial defense: for preprocessed annotations it hashes the generated input, not every original/preprocessor input, and it does not validate every imported CMI CRC. Production needs Dune freshness/dependency tracking. Repeated repository install builds were warm/no-op; no clean full-repository build time was measured.

Five sequential warm samples per operation; wall-clock medians from [measure.py](</tmp/ox-lint-spike/measure.py>) and [timing.tsv](</tmp/ox-lint-spike/timing.tsv>):

| Operation | Median seconds |
|---|---:|
| Read/digest-check + raw Typedtree traversal, existing Nix shell | 0.097 |
| Full type classification + discarded-result rule, existing Nix shell | 0.427 |
| No-op install build, existing Nix shell | 0.150 |
| Nix entry + no-op install build | 0.441 |
| Nix entry + full typed rule | 0.743 |

The probe classifies every expression for telemetry. Candidate-only classification could be cheaper but was not measured. These warmed local corpus figures are not consumer/CI guarantees, cold-cache measurements or test-suite timings.

## 8. Compiler API and migration exposure

**Real but bounded by the exact pin; isolate it.** Dependencies include Cmt_format, Config, Typedtree, Tast_iterator, Types, Data_types, Ctype, Env, Envaux, Load_path, Clflags, Path, Longident, Location, Printtyp and compiler UID types. These are compiler implementation APIs, not a stable interchange format.

Concrete pinned assumptions encountered:

- Texp_ident is a record with path/lid/desc/kind/unique_use/mode.
- Texp_apply includes application-position, locality and zero-allocation data; arguments are Arg(expression, sort) or Omitted.
- Constructor patterns include extra representation fields. Exception origin is a separate Text_rebind node, not UID equality.
- Env.lookup_value returns a triple; visible includes are Clflags.visible_include records, hidden includes are strings.
- Envaux.reset_cache takes its labelled bool **without a trailing unit argument**. The initial compile error and correction are preserved in [compile-failure1.log](</tmp/ox-lint-spike/compile-failure1.log>) and [compile.log](</tmp/ox-lint-spike/compile.log>).

Recommended seam: a compiler-version-specific adapter for reading, environment/load-path setup, node extraction, canonical identity/type checks and mode extraction. On each pin change, rebuild it and rerun golden fixtures for aliases, opens, shadowing, type aliases, modes, docs, missing/stale inputs and accepted blind spots. Magic checks catch format mismatch, not every semantic change. No compiler migration was attempted; compatibility beyond **5.4.0+ox** is not claimed.

## Prototype and exact reproduction commands

Run from /home/ribelo/projects/ribelo/ocaml/ox. Main artifacts: [metadata.ml](</tmp/ox-lint-spike/metadata.ml>), [spike.ml](</tmp/ox-lint-spike/spike.ml>), [fixture.ml](</tmp/ox-lint-spike/fixture.ml>), [check.py](</tmp/ox-lint-spike/check.py>), [measure.py](</tmp/ox-lint-spike/measure.py>), and the [scratch Dune rule](</tmp/ox-lint-spike/dune-probe/dune>). Fixture functions are compiled, not executed.

~~~sh
nix develop -c ocamlc -version
nix develop -c dune build @install
nix develop -c ocamlfind ocamlopt -package compiler-libs.common -linkpkg -o /tmp/ox-lint-spike/metadata /tmp/ox-lint-spike/metadata.ml
nix develop -c ocamlfind ocamlopt -package compiler-libs.common -linkpkg -o /tmp/ox-lint-spike/spike /tmp/ox-lint-spike/spike.ml
nix develop -c ocamlfind ocamlc -package eio -bin-annot -c /tmp/ox-lint-spike/fixture.ml

# Discover today's CMTs, including hidden Dune object directories.
python3 - <<'PY'
from pathlib import Path
Path('/tmp/ox-lint-spike/cmt-list.txt').write_text(''.join(str(f) + '\n' for f in sorted(Path('_build/default/lib').rglob('*.cmt'))))
PY
nix develop -c sh -c '/tmp/ox-lint-spike/metadata $(tr "\n" " " < /tmp/ox-lint-spike/cmt-list.txt)' > /tmp/ox-lint-spike/metadata.tsv
nix develop -c sh -c '/tmp/ox-lint-spike/spike --sites --paths $(tr "\n" " " < /tmp/ox-lint-spike/cmt-list.txt)' > /tmp/ox-lint-spike/corpus.tsv 2> /tmp/ox-lint-spike/corpus.log
# Intentionally exits 1 on findings; 2 means a reader/check failure.
nix develop -c /tmp/ox-lint-spike/spike --sites --paths /tmp/ox-lint-spike/fixture.cmt
# Intentionally exits 1: 5 findings, 0 failures.
nix develop -c python3 /tmp/ox-lint-spike/check.py
nix develop -c python3 /tmp/ox-lint-spike/measure.py
nix develop -c sh /tmp/ox-lint-spike-interfaces/run.sh
# Helper script exits 0 and regenerates interface/mode evidence.
nix develop -c dune build --root /tmp/ox-lint-spike/dune-probe @install
nix develop -c dune build --root /tmp/ox-lint-spike/dune-probe @lint
# @lint intentionally fails on its sample result discard, not on CMT reading.
~~~

Recreate the deliberate negative cases:

~~~sh
printf '%s\n' 'let dropped () = ignore (Ok 1 : (int, string) result)' > /tmp/ox-lint-spike/stale.ml
nix develop -c ocamlc -bin-annot -c /tmp/ox-lint-spike/stale.ml
printf '%s\n' 'let dropped () = () (* Fixed; annotation intentionally not rebuilt. *)' > /tmp/ox-lint-spike/stale.ml
nix develop -c /tmp/ox-lint-spike/spike /tmp/ox-lint-spike/stale.cmt
# Expected exit 2, source digest mismatch.
nix develop -c /tmp/ox-lint-spike/spike --allow-stale /tmp/ox-lint-spike/stale.cmt
# Expected exit 1, obsolete violation.
nix develop -c ocamlc -c /tmp/ox-lint-spike/noannot.ml
python3 /tmp/ox-lint-spike/wrong_magic.py
nix develop -c /tmp/ox-lint-spike/spike /tmp/ox-lint-spike/noannot.cmt
nix develop -c /tmp/ox-lint-spike/spike /tmp/ox-lint-spike/wrong-magic.cmt
# Both expected exit 2.
~~~

[check.py](</tmp/ox-lint-spike/check.py>) deliberately asserts the sampled 113/40/8 corpus and existing negative fixtures, not a general linter contract. Concurrent/source changes can legitimately alter these counts. [corpus.tsv](</tmp/ox-lint-spike/corpus.tsv>) is the exact preserved candidate/finding inventory.

## Unestablished points

- Behavior-documentation policy/semantic truth, module-doc inheritance, and a general semantic query layer for every mode axis; inferred parameter modes may remain bounds.
- Native-only executable coverage without explicit annotation dependencies.
- Clean/full build cost, cold I/O, consumer scale, installed-CMT relocation, multiple contexts and other compiler versions.
- Cross-unit/nested exception rebinding, functors/first-class modules, value aliases/higher-order calls, and whole-program/transitive suspension closure.
- Complete dependency freshness from CMT metadata alone; policy decisions for intentional corpus discards.

**Bottom line:** the typed discarded-result tier is demonstrated and practical on the exact pin. Make it build-context-aware and fail-closed, with a documented decidable form—not name matching or a claim of whole-program safety.
