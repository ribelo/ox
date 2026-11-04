#!/usr/bin/env bash
# ^nlet-4eh4: local and yielding values survive let%bind; their refusals still fire after it.
set -uo pipefail
compiler="$1"
ppx="$2"
include="$(cd "$3" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
status=0
includes=()
while IFS= read -r dir; do includes+=(-I "$dir"); done < <(ocamlfind query -recursive eio)
compile() {
  "$ppx" "$1" >"$tmp/${1##*/}" 2>"$tmp/out" || return 3
  (cd "$tmp" && "$compiler" -I "$include" "${includes[@]}" -c "${1##*/}") >"$tmp/out" 2>&1
}
for file in good_*.ml; do
  if compile "$file"; then echo "ok: $file compiles"; else echo "FAIL: $file should compile"; cat "$tmp/out"; status=1; fi
done
for file in bad_*.ml; do
  expected="$(sed -n 's/^(\* expect: \(.*\) \*)$/\1/p' "$file")"
  rc=0
  compile "$file" || rc=$?
  if [[ $rc != 2 ]]; then echo "FAIL: $file expected compiler status 2, got $rc"; cat "$tmp/out"; status=1
  elif grep -Eq "$expected" "$tmp/out"; then echo "ok: $file refused ($expected)"
  else echo "FAIL: wrong refusal: $file"; cat "$tmp/out"; status=1; fi
done
exit "$status"
