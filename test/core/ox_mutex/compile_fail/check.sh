#!/usr/bin/env bash
# ^ncrit-lpe4: Ox.Mutex positive controls and refusals.
set -uo pipefail
compiler="$1"
include="$(cd "$2" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
status=0
includes=()
while IFS= read -r dir; do includes+=(-I "$dir"); done < <(ocamlfind query -recursive eio)
compile() {
  cp "$1" "$tmp/"
  if [[ -f "${1%.ml}.mli" ]]; then
    cp "${1%.ml}.mli" "$tmp/"
    (cd "$tmp" && "$compiler" -I "$include" "${includes[@]}" -c "${1##*/}"i) >"$tmp/out" 2>&1 || {
      echo "FAIL: authored interface ${1%.ml}.mli must compile before testing its implementation"
      cat "$tmp/out"
      exit 1
    }
  else
    echo "FAIL: missing authored interface ${1%.ml}.mli"
    exit 1
  fi
  (cd "$tmp" && "$compiler" -I "$include" "${includes[@]}" -c "${1##*/}") >"$tmp/out" 2>&1
}
for file in good_*.ml; do
  if compile "$file"; then echo "ok: $file compiles"; else echo "FAIL: $file should compile"; cat "$tmp/out"; status=1; fi
done
for file in bad_*.ml; do
  expected="local|global|yielding|unyielding|escape"
  if [[ "$file" == bad_brand.ml ]]; then expected="existential"; fi
  rc=0
  compile "$file" || rc=$?
  if [[ $rc != 2 ]]; then echo "FAIL: $file expected native compiler status 2, got $rc"; cat "$tmp/out"; status=1
  elif sed -n '/^Error:/,$p' "$tmp/out" | grep -Eq "$expected"; then echo "ok: $file refused ($expected)"
  else echo "FAIL: wrong refusal: $file"; cat "$tmp/out"; status=1; fi
done
exit "$status"
