# Interfaces, docstrings and modes: pinned OxCaml spike

## Verdicts

- **A — reachable.** Every one of the 97 source interfaces under `lib/**/*.mli` has a matching `.cmti`. All 1,301 declared vals expose their name, complete source span, typed type and attached docstrings directly from the typed artifact. A split source/typed implementation is not required for these inputs.
- **B — inspectable.** The pinned parser and typed artifacts work for all six requested files. Explicit local/global annotations, effective arrow locality, function-parameter modes, value/field modalities and type kinds are accessible. Not every inferred implementation parameter has a single constant mode; some retain solver bounds.

These verdicts concern information availability, not the correctness of a future behavior-documentation or suspension rule.

## Reproduction and artifacts

Workspace: `/home/ribelo/projects/ribelo/ocaml/ox`. Compiler: `5.4.0+ox`, confirmed by executing the final script inside the repository's Nix development shell. No repository files were changed, staged or committed; no build refresh was needed. Final `git status --short` returned no output.

From the workspace root, run:

```sh
nix develop -c sh /tmp/ox-lint-spike-interfaces/run.sh \
  > /tmp/ox-lint-spike-interfaces/run.stdout \
  2> /tmp/ox-lint-spike-interfaces/run.stderr
```

Verified exit status: **0**. Output:

```text
5.4.0+ox
Coverage and mode summaries saved under /tmp/ox-lint-spike-interfaces
```

The two stderr messages are findlib duplicate-interface warnings for `opttopdirs.cmi` and `topdirs.cmi` in the standard-library and compiler-libs directories, not compilation or extraction failures. See [run output](</tmp/ox-lint-spike-interfaces/run.stdout>) and [run stderr](</tmp/ox-lint-spike-interfaces/run.stderr>).

Complete commands are in [run.sh](</tmp/ox-lint-spike-interfaces/run.sh>). It compiles [probe.ml](</tmp/ox-lint-spike-interfaces/probe.ml>), extracts both manifests, runs all six source/artifact pairs, compiles fresh mode controls and writes the summaries. Its compiler command is:

```sh
nix develop -c ocamlfind ocamlc \
  -package compiler-libs.common,yojson -linkpkg \
  -o /tmp/ox-lint-spike-interfaces/probe.exe \
  /tmp/ox-lint-spike-interfaces/probe.ml
```

Inventory inputs: [interfaces.list](</tmp/ox-lint-spike-interfaces/interfaces.list>) and [cmti.list](</tmp/ox-lint-spike-interfaces/cmti.list>), collected with complete repository glob searches, then sorted. Evidence: [source JSONL](</tmp/ox-lint-spike-interfaces/source-all.jsonl>), [typed JSONL](</tmp/ox-lint-spike-interfaces/typed-all.jsonl>), [coverage summary](</tmp/ox-lint-spike-interfaces/coverage-summary.json>), [six-file mode JSONL](</tmp/ox-lint-spike-interfaces/modes-six.jsonl>) and [mode summary](</tmp/ox-lint-spike-interfaces/modes-summary.stdout>). Comparison code: [analyze.py](</tmp/ox-lint-spike-interfaces/analyze.py>) and [analyze_modes.py](</tmp/ox-lint-spike-interfaces/analyze_modes.py>).

## A. Interface coverage and documentation

Verified by independently parsing all original source interfaces and traversing all typed signatures:

| Check | Result |
|---|---:|
| Source interfaces / typed interface artifacts | 97 / 97 |
| Source interfaces missing an artifact | 0 |
| Unmapped artifact source names | 0 |
| Artifact source digests matching their resolved input | 97 |
| Source val declarations / typed val declarations | 1,301 / 1,301 |
| Missing or extra typed val declarations | 0 / 0 |
| Duplicate declaration keys | 0 |
| Full declaration-span mismatches | 0 |
| Vals with attached docs, source / typed | 488 / 488 |
| Attached-document text or span mismatches | 0 |
| Docs differing between the two typed attribute locations | 0 |
| Typed vals with a nonempty printed type | 1,301 |
| External declarations in this interface corpus | 0 |

Keys use normalized source filename, val name and start/end byte positions; complete line/column/byte/ghost spans are additionally compared. Traversal includes nested signatures, not only top-level vals.

**PPX caveat:** 15 artifacts name a `.pp.mli` source. Their source files exist in Dune's default build tree, while their recorded `cmt_builddir` is `/workspace_root`. The probe resolves these to the existing build-tree file before checking the digest. Comparison normalizes `.pp.mli` to `.mli` for this corpus. Thus 82 digests attest to original repository source and 15 to preprocessed compiler input. The latter are not a proof that every PPX output was freshly regenerated from its current original source; independently matching val names, spans and docs provides additional evidence, but does not replace rebuilding for a production gate.

### Working API

The pinned API is `Cmt_format.read_cmt` for **both** artifact extensions; dispatch on `Interface` versus `Implementation`:

```ocaml
let info = Cmt_format.read_cmt path in
match info.cmt_annots with
| Cmt_format.Interface signature ->
    iterator.Tast_iterator.signature iterator signature
| Cmt_format.Implementation structure ->
    iterator.Tast_iterator.structure iterator structure
| _ -> failwith "unsupported annotation kind"
```

For a `Typedtree.value_description`, the working probe reads:

- `val_name.txt` and `val_loc`;
- `val_desc.ctyp_type`, printed by `Printtyp.type_scheme`;
- `val_attributes` and `val_val.val_attributes`. Both retain the same `ocaml.doc` payloads across all 1,301 vals.

The observed doc payload is:

```ocaml
PStr [{ pstr_desc = Pstr_eval
  ({ pexp_desc = Pexp_constant
      { pconst_desc = Pconst_string (text, _, _); _ }; _ }, _); _ }]
```

Source parsing initializes docstring handling explicitly:

```ocaml
Lexer.handle_docstrings := true;
Docstrings.init ();
Lexer.init ();
Location.init lexbuf path;
Parse.interface lexbuf
```

### Concrete successful extraction

For [resource interface:10–12](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/resource.mli#L10-L12>), source and typed extraction both returned:

```text
name: use_in_scope
type: sw:Eio.Switch.t -> (unit -> 'a) @ local -> ('a -> unit) -> 'a
val span: line 10, columns [0,80), bytes [677,757)
doc span: line 11 column 0 to line 12 column 50, bytes [758,894)
doc text:
 [use_in_scope ~sw acquire release] runs [acquire] in the calling fiber, registers
    [release] on [sw] and returns the resource. 
```

**Rule-design boundary:** 813 vals have no attached `ocaml.doc`. This is not automatically 813 behavior-convention violations. For example, [duration interface:1–8](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/duration.mli#L1-L8>) has a module-level statement about suspension, cancellation and finalizers, while its `zero` val has no attached doc. Whether a rule accepts module-level defaults, requires individual statements, or uses a structured attribute remains undecided. The probe extracts attachment, not whether prose is true or sufficiently explicit. Its doc list intentionally excludes floating `ocaml.text` comments and module-doc inheritance.

## B. Modes in all six requested files

Both parsing and typed-artifact loading completed successfully for every row:

| Source | Source mode/modality atoms | Typed evidence |
|---|---|---|
| [duration.mli](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/duration.mli>) | portable ×2, contended ×1 | 40 arrow nodes; effective portable val modality; written and effective type kind |
| [cause.mli](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/cause.mli>) | portable ×1 | 12 arrow nodes; effective portable val modalities |
| [resource.mli](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/resource.mli>) | local ×2 | 8 arrow nodes; both written local argument annotations retained |
| [scope.mli](</home/ribelo/projects/ribelo/ocaml/ox/lib/ox/scope.mli>) | none in current source | 24 arrow nodes with effective modes; absence is source absence, not parser loss |
| [sqlite.ml](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/sqlite.ml>) | global ×9, portable ×81, local ×77 | 86 arrow nodes; 229 parameter nodes; 77 written local and 81 portable atoms retained across arrows/parameters/expressions; 9 written field modalities |
| [ox_sql_dsl.ml](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql_dsl/ox_sql_dsl.ml>) | portable ×4, local ×7 | 287 arrow nodes; 39 parameter nodes; all 7 local and 4 portable atoms retained |

Arrow counts include nested function types and annotated constraints; they are not function counts. SQLite's nine `global_` annotations are record-field modalities, not nine explicit global function arguments.

The exact implementation artifacts used are [SQLite cmt](</home/ribelo/projects/ribelo/ocaml/ox/_build/default/lib/sql/.ox_sql.objs/byte/ox_sql__Sqlite.cmt>) and [SQL DSL cmt](</home/ribelo/projects/ribelo/ocaml/ox/_build/default/lib/sql_dsl/.ox_sql_dsl.objs/byte/ox_sql_dsl.cmt>). Interface artifact paths are in [run.sh](</tmp/ox-lint-spike-interfaces/run.sh>).

### Surviving structures

- **Parsetree:** `Ast_iterator.modes` sees located `Mode text` atoms, and `.modalities` sees `Modality text` atoms. The ordinary pinned parser handles `@ local`, `@@ portable`, `global_` and kind modifiers; no alternate parser was needed.
- **Typed arrows:** `Ttyp_arrow (label, argument_type, argument_modes, result_type, result_modes)` retains constant effective modes and written located atoms. Locality is classified structurally via `mode_modes.Mode.Alloc.areality` and `Mode.Locality.Const.Global | Local`, not by searching a pretty-printed type.
- **Typed function parameters:** `fp_mode : Mode.Alloc.l modes` retains written atoms and effective solver modes/bounds, with `fp_loc` and `fp_kind` for attribution.
- **Typed expression mode annotations:** `Texp_mode` in `exp_extra` preserves written modes such as a portable binding's annotation.
- **Typed value modalities:** `Valmi_sig_value` exposes `moda_modalities` and `moda_desc`. Module-wide portable defaults appear in effective modalities even where a val's own written list is empty.
- **Typed record fields:** `ld_modalities` exposes effective and written modalities. These are reached through `typ_kind`; this pinned `Tast_iterator` does not offer a label-declaration callback.
- **Typed type declarations:** `typ_jkind_annotation` retains the written kind, and `typ_type.type_jkind` exposes its semantic kind. The probe prints the latter with `Jkind.format Env.empty`.

Concrete outputs in [mode summary](</tmp/ox-lint-spike-interfaces/modes-summary.stdout>):

- Duration's `t` has effective kind `value mod portable contended`, and its written kind is retained. Its `zero` value's effective modality includes `portable` despite an empty written-val modality list.
- Resource's `use_in_scope` acquisition callback has effective locality `local` and a written local atom at line 10, columns 53–58. Its effective return locality is also local; this must not be mistaken for a second explicitly written annotation.
- In [SQL DSL:82](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql_dsl/ox_sql_dsl.ml#L82>), `transaction`'s `resource` and `f` parameters retain written local atoms and local effective bounds; `rollback` has no written annotation and a global effective comonadic mode.
- SQLite's [raw field:5](</home/ribelo/projects/ribelo/ocaml/ox/lib/sql/sqlite.ml#L5>) retains a written global modality and an effective modality whose locality component is global.

### Fresh control: local, global, implicit global, unique, portable

[fixture.mli](</tmp/ox-lint-spike-interfaces/fixture.mli>) and [fixture.ml](</tmp/ox-lint-spike-interfaces/fixture.ml>) were compiled on the pinned compiler using `-bin-annot`, then parsed and read through both artifact kinds. Complete commands are in [run.sh](</tmp/ox-lint-spike-interfaces/run.sh>), results in [fixture JSONL](</tmp/ox-lint-spike-interfaces/fixture.jsonl>).

```text
take_local:    arg locality local;  written [local]
take_global:   arg locality global; written [global]
take_default:  arg locality global; written []
take_unique:   arg locality global; written [unique]; effective uniqueness unique
take_portable: arg locality global; written [portable]; effective portability portable
```

The implementation control also retains each explicit atom. Importantly, an unannotated implementation parameter has a `global .. local` locality interval while its exported signature argument is global. A linter must not interpret an empty parameter annotation list as proof of an effective global mode, nor assume every `fp_mode` is a constant. Declared-arrow locality, explicit syntax and inferred implementation bounds are different questions.

## Actual failed exploratory attempts, then corrections

All compiler/API failures below are from the pinned compiler, not guessed compatibility concerns. The final prototype compiles and runs after the corrections.

| Actual error | Correction and preserved log |
|---|---|
| `Error: Unbound module Mode.Alloc.Atom` | `Atom` is a GADT constructor of `Mode.Alloc.atom`, not a submodule. [log](</tmp/ox-lint-spike-interfaces/mode_queries.err>) |
| `Error: Unbound record field txt` | Qualify the located parser atom as `m.Location.txt`. [log](</tmp/ox-lint-spike-interfaces/compile.stderr>) |
| `This pattern matches values of type 'a * 'b * 'c ... Typedtree.pattern_desc.Tpat_var` | `Tpat_var` is an inline record; use `Tpat_var {name; _}`. [log](</tmp/ox-lint-spike-interfaces/compile-2.stderr>) |
| `Tparam_optional_default expects 3 argument(s), but is applied here to 2 argument(s)` | Match pattern, default expression and sort. [log](</tmp/ox-lint-spike-interfaces/compile-4.stderr>) |
| `There is no field label_declaration within type Tast_iterator.iterator` | Read record labels through `typ_kind` in the type-declaration callback. [log](</tmp/ox-lint-spike-interfaces/field-hook-failure.stderr>) |

The initial comparison incorrectly treated the 15 PPX source names as absent original interfaces, and initially could not resolve their recorded build directory. These were mapping mistakes, not missing artifacts; normalized comparison and build-tree digest resolution remove them. Exploratory Python helper bugs also occurred (a newline-quoting syntax error and access to a span on artifact metadata rather than AST rows); they were corrected before the successful full comparison.

Exported mode API inspection can be reproduced with:

```sh
nix develop -c sh -c 'ocamlc -I +compiler-libs -i \
  /tmp/ox-lint-spike-interfaces/mode_queries.ml \
  > /tmp/ox-lint-spike-interfaces/mode_queries-final.txt'
```

See [mode_queries.ml](</tmp/ox-lint-spike-interfaces/mode_queries.ml>), [expanded API](</tmp/ox-lint-spike-interfaces/mode_queries-final.txt>) and the installed [Typedtree interface](</home/ribelo/.cache/opam/5.4.0+ox/lib/ocaml/compiler-libs/typedtree.mli>).

## Remaining limits

1. Existing-artifact coverage is verified; no clean full-library build was performed. Production analysis should build first, validate freshness and fail on missing/partial artifacts. PPX input freshness needs the qualification above.
2. Comment availability does not prove behavior, suspension safety, cancellation behavior or finalizer behavior. Documentation vocabulary and module-level inheritance need an explicit rule contract.
3. Inferred parameter modes may remain variables with bounds. The probe does not solve or mutate them, and has not implemented a general semantic mode-query layer for every axis or every AST construct.
4. Typed defaults can lose attribution to the original module-wide directive even though effective portability survives. Retain the source pass when a diagnostic needs to distinguish explicit spelling from inherited/default behavior.
5. This is a throwaway information-access probe, not a production linter. Nested-module qualified identities, arbitrary PPX provenance, build-context selection, stripped-doc artifacts, generative type paths and compiler-version adaptation are not fully engineered. Current-corpus extraction is complete, but the Python manifest and PPX mapping are corpus-specific.

**Go for this half of the spike:** interface docs and OxCaml modes are accessible without a replacement parser or a guessed upstream API. The implementation/effect-analysis half still needs its independent verdict.
