#!/usr/bin/env bash
# ^safe-p9cw ^safe-8peq ^safe-5a9k: manual installed public process API proof.
# Usage: bash check-installed.sh EXTERNAL_PREFIX
# Requires the matching compiler/findlib, Eio and timeout on PATH. Install separately
# with dune install --prefix; this script never installs or uses checkout modules.
# Consumer sources and compilation CWD are copied to /var/tmp outside Git ancestors.
set -euo pipefail
trap 'status=$?; printf "installed process proof terminal exit=%d\n" "$status"' EXIT
reject() { printf 'installed process proof rejects input: %s\n' "$*" >&2; exit 2; }
[[ "$#" = 1 ]] || reject "usage: $0 EXTERNAL_PREFIX"
prefix="$(realpath -e "$1")"
[[ -d "$prefix/lib" ]] || reject "missing installed lib directory: $prefix"
assets="$(dirname "$(realpath -e "$0")")/consumer"
outside_checkout() {
  local directory="$1"
  while :; do
    [[ ! -e "$directory/.git" && ! -f "$directory/dune-project" ]] ||
      reject "source/build ancestor: $directory"
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
  done
}
outside_checkout "$prefix"
export OCAMLPATH="$prefix/lib"
for package in ox ox_caps ox_caps.door ox_process; do
  found="$(realpath -e "$(ocamlfind query "$package")")"
  if [[ "$package" = ox_caps.door ]]; then
    expected="$prefix/lib/ox_caps/door"
  else
    expected="$prefix/lib/$package"
  fi
  [[ "$found" = "$expected" ]] || reject "package $package escaped prefix: $found"
  for file in "$found"/*.cmi "$found"/*.cmxa "$found"/*.a; do
    [[ -f "$file" ]] || reject "missing installed native artifact: $file"
    resolved="$(realpath -e "$file")"
    [[ "$resolved" = "$prefix"/* ]] || reject "artifact links outside prefix: $file"
  done
  printf 'installed package %s: %s\n' "$package" "$found"
done
scratch="$(mktemp -d /var/tmp/ox-process-installed-consumer.XXXXXX)"
scratch="$(realpath -e "$scratch")"
outside_checkout "$scratch"
printf 'consumer evidence: %s\n' "$scratch"
for stem in positive negative_child negative_supervised; do
  cp "$assets/$stem.ml" "$assets/$stem.mli" "$scratch/"
done
cd "$scratch"
outside_checkout "$(pwd -P)"
packages=ox_process,ox_caps.door,eio_main
status=0
ocamlfind ocamlopt -package "$packages" -c positive.mli > positive.log 2>&1 || status=$?
printf 'positive interface compile exit=%d\n' "$status"
[[ "$status" = 0 ]] || exit "$status"
status=0
ocamlfind ocamlopt -I . -package "$packages" -linkpkg positive.ml -o positive.exe >> positive.log 2>&1 || status=$?
printf 'positive installed consumer compile exit=%d\n' "$status"
[[ "$status" = 0 ]] || exit "$status"
status=0
timeout 10s ./positive.exe >> positive.log 2>&1 || status=$?
printf 'positive real-OS grace/retirement runtime exit=%d\n' "$status"
[[ "$status" = 0 ]] || exit "$status"
for stem in negative_child negative_supervised; do
  status=0
  ocamlfind ocamlopt -package "$packages" -c "$stem.mli" > "$stem.log" 2>&1 || status=$?
  printf '%s interface compile exit=%d\n' "$stem" "$status"
  [[ "$status" = 0 ]] || exit "$status"
  status=0
  ocamlfind ocamlopt -I . -package "$packages" -c "$stem.ml" >> "$stem.log" 2>&1 || status=$?
  printf '%s wall-clock compile exit=%d (expected 2)\n' "$stem" "$status"
  [[ "$status" = 2 ]] || reject "$stem did not reject the wall clock"
  grep -Fq 'Eio.Time.clock' "$stem.log" && grep -Fq 'Eio.Time.Mono.t' "$stem.log" ||
    reject "$stem failed for something other than the clock type mismatch"
done
printf 'installed public Mono process proof passed\n'
