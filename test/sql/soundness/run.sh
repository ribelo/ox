#!/usr/bin/env bash
# ^nsql-4m2q ^nsql-c2jw: typed SQL rejects invalid expressions at compile time.
set -u

cmxa="$1"
fixture_dir="$(dirname "$0")"
sql_obj_dir="$(dirname "$cmxa")/.ox_sql.objs/byte"
ox_obj_dir="$(dirname "$cmxa")/../ox/.ox.objs/byte"
dsl_obj_dir="$(dirname "$cmxa")/../sql_dsl/.ox_sql_dsl.objs/byte"
tmp_dir="${TMPDIR:-/tmp}/ox-sql-soundness-negative-$$"
mkdir -p "$tmp_dir"

status=0

for src in "$fixture_dir"/*_negative.ml; do
  name="$(basename "$src")"
  log="$tmp_dir/$name.log"
  obj="$tmp_dir/${name%.ml}.cmx"

  if ocamlfind ocamlopt \
      -package "eio,eio_main,unix,threads" \
      -I "$dsl_obj_dir" -I "$ox_obj_dir" -I "$sql_obj_dir" \
      -c "$src" -o "$obj" >"$log" 2>&1; then
    echo "expected compile failure, but fixture compiled: $name"
    status=1
  elif ! grep -Eiq "type|expected|but|unify|compatible|constructor|record field" "$log"; then
    echo "fixture failed for the wrong reason: $name"
    sed -n '1,120p' "$log"
    status=1
  fi
done

rm -rf "$tmp_dir"
exit "$status"
