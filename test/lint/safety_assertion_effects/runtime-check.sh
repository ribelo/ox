#!/usr/bin/env bash
set -euo pipefail
# ^safe-28t6: actual paired compiler/runtime consumers, never a source-shape check.
EVIDENCE=$(realpath "$1")
WORK=$(mktemp -d /tmp/ox-assertion-runtime.XXXXXX)
case "$WORK" in /tmp/ox-assertion-runtime.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "$WORK"' EXIT
cp "$EVIDENCE"/runtime_{broken,repaired}.{ml,mli} "$WORK/"
cd "$WORK"
for mode in normal noassert; do
  flags=()
  if [ "$mode" = noassert ]; then flags=(-noassert); fi
  for program in broken repaired; do
    ocamlc -c "runtime_$program.mli"
    ocamlc "${flags[@]}" -o "$program-$mode" "runtime_$program.ml"
  done
  expected=1
  if [ "$mode" = noassert ]; then expected=0; fi
  [ "$(./broken-$mode)" = "$expected" ]
  [ "$(./repaired-$mode)" = 1 ]
  set +e
  output=$(./repaired-$mode invalid)
  status=$?
  set -e
  [ "$output" = 1 ] && [ "$status" = 7 ]
done
