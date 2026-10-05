#!/usr/bin/env bash
# ^safe-p9cw ^safe-8peq ^safe-5a9k: permanent, installed public API controls.
set -euo pipefail
consumer=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$consumer/.." && pwd -P)
export OCAMLPATH="$root/prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
export CAML_LD_LIBRARY_PATH="$root/prefix/lib/stublibs${CAML_LD_LIBRARY_PATH:+:$CAML_LD_LIBRARY_PATH}"
export LC_ALL=C
mkdir -p "$root/evidence" "$consumer/artifacts"
cd -- "$consumer/artifacts"
test "$(ocamlfind query ox_sql)" = "$root/prefix/lib/ox_sql"
test "$(ocamlfind query ox_test)" = "$root/prefix/lib/ox_test"
compile=(ocamlfind ocamlopt -package ox_sql,ox_test,eio.mock,alcotest -I .)
for module in positive sql_monotonic main; do
  "${compile[@]}" -c "$consumer/$module.mli" -o "$module.cmi"
  "${compile[@]}" -c "$consumer/$module.ml" -o "$module.cmx"
done
for module in pool_wall pool_function migrate_wall migrate_function run_to_wall run_to_function; do
  "${compile[@]}" -c "$consumer/$module.mli" -o "$module.cmi"
  set +e
  "${compile[@]}" -c "$consumer/$module.ml" -o "$module.cmx" >"$root/evidence/$module.log" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status" >"$root/evidence/$module.status"
  test "$status" -eq 2
  # Reject the precise clock mismatch, not an unrelated build/link failure.
  python3 - "$root/evidence/$module.log" "$module" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert 'Error: The value clock has type' in text and 'Eio.Time.Mono.ty Eio.Time.Mono.t' in text, text
assert sys.argv[2] + '.ml' in text and '~clock' in text, text
if sys.argv[2].endswith('_function'):
    assert 'unit -> float' in text, text
else:
    assert 'float' in text and 'Mtime.t' in text and 'Types for tag `Clock are incompatible' in text, text
assert 'Unbound' not in text and 'not found' not in text, text
PY
done
"${compile[@]}" -linkpkg sql_monotonic.cmx main.cmx -o main.exe
./main.exe >"$root/evidence/runtime.stdout" 2>"$root/evidence/runtime.stderr"
printf '%s\n' 'sql-monotonic-runtime: 15 native wall-jump/duration/cleanup controls passed' >"$root/evidence/runtime.expected"
cmp "$root/evidence/runtime.expected" "$root/evidence/runtime.stdout"
printf '%s\n' 'sql-monotonic-installed: public positive + 6 precise clock rejections + 15 runtime controls passed'
