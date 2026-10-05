#!/usr/bin/env bash
set -euo pipefail
DRIVER=$(realpath "$1")
EVIDENCE=$(realpath "$2")
CLEAN=$(realpath "$3")
VIOLATING=$(realpath "$4")
WORK=$(mktemp -d /tmp/ox-assertion-source.XXXXXX)
case "$WORK" in /tmp/ox-assertion-source.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "$WORK"' EXIT
cp -R "$EVIDENCE/." "$WORK/"
cd "$WORK"
dune build --root "$WORK" @check
for kind in clean violating; do
  fixture="$CLEAN"
  if [ "$kind" = violating ]; then fixture="$VIOLATING"; fi
  mkdir -p "$WORK/$kind"
  cp "$fixture" "$(dirname "$fixture")/assertion_effects.mli" "$WORK/$kind/"
  (
    cd "$WORK/$kind"
    ocamlc -bin-annot -c assertion_effects.mli
    ocamlc -bin-annot -c assertion_effects.ml
  )
done
operations_sites=
while read -r name effects unknown sites; do
  annotation="$WORK/_build/default/.evidence.objs/byte/$name.cmt"
  case "$name" in clean/*|violating/*) annotation="$WORK/$name.cmt" ;; esac
  "$DRIVER" "$WORK/$name.ml" "$annotation" "$effects" "$unknown" "$sites"
  if [ "$name" = operations ]; then operations_sites=$sites; fi
done < expectations
[ -n "$operations_sites" ]
failed=0
for control in duplicate-effect-site wrong-effect-site; do
  status=0
  "$DRIVER" "$WORK/operations.ml" "$WORK/_build/default/.evidence.objs/byte/operations.cmt" \
    6 0 "$operations_sites" "--$control" > "$WORK/$control.out" 2> "$WORK/$control.err" || status=$?
  printf 'oracle control %s: same effects=6 unknown=0; exit=%s (expected 2)\n' "$control" "$status"
  if [ "$status" != 2 ]; then
    failed=1
  elif ! awk '/exact diagnostic multiset mismatch/ {found=1} END {exit !found}' "$WORK/$control.err"; then
    sed -n '1,60p' "$WORK/$control.err" >&2
    failed=1
  fi
  sed -n '1,60p' "$WORK/$control.err" >&2
done
exit "$failed"
