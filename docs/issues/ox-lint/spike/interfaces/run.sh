#!/bin/sh
# Run from /home/ribelo/projects/ribelo/ocaml/ox, inside nix develop.
set -eu
D=/tmp/ox-lint-spike-interfaces
ocamlc -version
ocamlfind ocamlc -package compiler-libs.common,yojson -linkpkg -o "$D/probe.exe" "$D/probe.ml"
xargs "$D/probe.exe" < "$D/interfaces.list" > "$D/source-all.jsonl"
xargs "$D/probe.exe" < "$D/cmti.list" > "$D/typed-all.jsonl"
python3 "$D/analyze.py" > "$D/coverage.stdout"
"$D/probe.exe" \
 lib/ox/duration.mli lib/ox/cause.mli lib/ox/resource.mli lib/ox/scope.mli \
 lib/sql/sqlite.ml lib/sql_dsl/ox_sql_dsl.ml \
 _build/default/lib/ox/.ox.objs/byte/ox__Duration.cmti \
 _build/default/lib/ox/.ox.objs/byte/ox__Cause.cmti \
 _build/default/lib/ox/.ox.objs/byte/ox__Resource.cmti \
 _build/default/lib/ox/.ox.objs/byte/ox__Scope.cmti \
 _build/default/lib/sql/.ox_sql.objs/byte/ox_sql__Sqlite.cmt \
 _build/default/lib/sql_dsl/.ox_sql_dsl.objs/byte/ox_sql_dsl.cmt \
 > "$D/modes-six.jsonl"
ocamlc -bin-annot -c -o "$D/fixture.cmi" "$D/fixture.mli"
ocamlc -bin-annot -I "$D" -c -o "$D/fixture.cmo" "$D/fixture.ml"
"$D/probe.exe" "$D/fixture.mli" "$D/fixture.ml" "$D/fixture.cmti" "$D/fixture.cmt" > "$D/fixture.jsonl"
python3 "$D/analyze_modes.py" > "$D/modes-summary.stdout"
printf 'Coverage and mode summaries saved under %s\n' "$D"
