#!/usr/bin/env bash
# ^safe-3osb: empty component sequences fail against the real Paths CMI.
set -euo pipefail
compiler="$1"
lint="$2"
common="${3%/*}"
caps="$4"
compile() {
  printf '%s\n' "$1" > input.ml
  "$compiler" -I "$lint" -I "$common" -I "$caps" -I +compiler-libs -c input.ml 2>&1
}
# Positive control includes legal empty alias sets and empty lexical components.
compile 'let _ = Paths.lid ("", [])
let _ = Paths.lid ("Stdlib", ["Result"; "value"])
let values caps = Paths.values ~caps []
let modules caps = Paths.modules ~caps []'
printf 'positive compiler-name control: pass\n'
for source in \
  'let _ = Paths.lid []' \
  'let value caps = Paths.value ~caps []' \
  'let module_ caps = Paths.module_ ~caps []' \
  'let values caps = Paths.values ~caps [[]]' \
  'let modules caps = Paths.modules ~caps [[]]'; do
  if output=$(compile "$source"); then
    printf 'accepted empty compiler name: %s\n' "$source" >&2
    exit 1
  fi
  case "$output" in
    *Paths.name*list*) ;;
    *list*Paths.name*) ;;
    *) printf 'unexpected rejection: %s\n%s\n' "$source" "$output" >&2; exit 1 ;;
  esac
  printf 'empty compiler name rejected: %s\n' "$source"
done
printf 'nonempty compiler-name boundary: pass\n'
