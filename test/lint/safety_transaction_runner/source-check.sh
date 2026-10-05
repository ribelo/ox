#!/usr/bin/env bash
# ^safe-ldtb ^safe-r1xw ^safe-y047: native MI-first build-tree-library acceptance.
set -euo pipefail
DRIVER=$(realpath "$1")
EVIDENCE=$(realpath "$2")
INSTALL_LIB=$(realpath --no-symlinks "$3")
CLEAN=$(realpath "$4")
VIOLATING=$(realpath "$5")
CORPUS=$(realpath "$6")
CORPUS_ANNOTATION=$(realpath "$7")
unset DUNE_SOURCEROOT DUNE_INSIDE_DUNE INSIDE_DUNE
export OCAMLPATH="$INSTALL_LIB${OCAMLPATH:+:$OCAMLPATH}"
WORK=$(mktemp -d /tmp/ox-transaction-source.XXXXXXXX)
case "$WORK" in /tmp/ox-transaction-source.*) ;; *) exit 2 ;; esac
trap 'rm -rf -- "$WORK"' EXIT
cp -R "$EVIDENCE/." "$WORK/"
chmod -R u+w "$WORK"
for kind in clean violating; do
  fixture="$CLEAN"; if [[ "$kind" = violating ]]; then fixture="$VIOLATING"; fi
  mkdir "$WORK/$kind"
  cp "$fixture" "$(dirname "$fixture")/transaction_runner.mli" "$WORK/$kind/"
  printf "(library (name fixture_%s) (wrapped false) (modules transaction_runner) (libraries ox_sql))\n" "$kind" > "$WORK/$kind/dune"
done
cd "$WORK"
dune build --root "$WORK" @check test_rollback.exe
controls_sites=
while read -r name defects unknown sites; do
  [[ "${name:0:1}" != "#" ]] || continue
  annotation="$WORK/_build/default/.transaction_cases.objs/byte/$name.cmt"
  case "$name" in
    no_sql) annotation="$WORK/_build/default/.transaction_no_sql.objs/byte/no_sql.cmt" ;;
    clean/*|violating/*) kind=${name%%/*}; annotation="$WORK/_build/default/$kind/.fixture_$kind.objs/byte/transaction_runner.cmt" ;;
  esac
  "$DRIVER" "$WORK/$name.ml" "$annotation" "$defects" "$unknown" "$sites"
  if [[ "$name" = controls ]]; then controls_sites=$sites; fi
done < expectations
[[ -n "$controls_sites" ]]
for control in duplicate-defect-site wrong-defect-site; do
  status=0
  "$DRIVER" "$WORK/controls.ml" "$WORK/_build/default/.transaction_cases.objs/byte/controls.cmt" \
    3 3 "$controls_sites" "--$control" > "$WORK/$control.out" 2> "$WORK/$control.err" || status=$?
  printf "oracle control %s: same defects=3 unknown=3; exit=%s (expected 2)\n" "$control" "$status"
  [[ "$status" = 2 ]]
  awk '/exact diagnostic multiset mismatch/ { found=1 } END {exit !found}' "$WORK/$control.err"
done
"$DRIVER" "$CORPUS" "$CORPUS_ANNOTATION" 0 0 -
"$WORK/_build/default/test_rollback.exe"
printf "native transaction sites, same-count reds, production migration and bounded rollback passed\n"
