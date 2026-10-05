#!/usr/bin/env bash
# ^safe-tlyw ^safe-zgfv ^safe-sw86 ^safe-czoe ^safe-y047: installed API proof.
# Usage: bash check-installed.sh EXTERNAL_PREFIX [ASSETS_DIRECTORY]
# Requires the matching OxCaml compiler/findlib, Eio and Python on PATH. Prefix must
# contain installed ox and ox_blocking libraries, not source/build symlinks.
# Assets may be copied to /var/tmp; no checkout/private-module compilation fallback.
set -eEuo pipefail
[[ "$#" = 1 || "$#" = 2 ]] || { printf 'usage: %s EXTERNAL_PREFIX [ASSETS_DIRECTORY]
' "$0" >&2; exit 2; }
prefix="$(realpath -e "$1")"
assets="$(realpath -e "${2:-$(dirname "$(realpath -e "$0")")}")"
outside_checkout() {
  local directory="$1"
  while :; do
    if [[ -e "$directory/.git" || -f "$directory/dune-project" ]]; then
      printf 'installed proof rejects source/build location: %s
' "$directory" >&2
      exit 2
    fi
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
  done
}
outside_checkout "$prefix"
export OCAMLPATH="$prefix/lib"
for package in ox ox_blocking; do
  found="$(realpath -e "$(ocamlfind query "$package")")"
  [[ "$found" = "$prefix/lib/$package" ]] || { printf 'installed package lookup escaped prefix: %s
' "$found" >&2; exit 2; }
  for file in "$found"/*.cmi "$found"/*.cmxa "$found"/*.a; do
    [[ -f "$file" ]] || exit 2
    resolved="$(realpath -e "$file")"
    [[ "$resolved" = "$prefix"/* ]] || { printf 'installed library links back to source: %s
' "$resolved" >&2; exit 2; }
  done
done
scratch="$(mktemp -d /var/tmp/ox-native-leases-installed.XXXXXX)"
[[ -d "$scratch" && "$scratch" = /var/tmp/ox-native-leases-installed.* ]] || exit 2
outside_checkout "$scratch"
trap 'rm -rf -- "$scratch"' EXIT
cp "$assets/consumer/main.ml" "$assets/consumer/main.mli" "$scratch/"
cd "$scratch"
bash "$assets/check-compile.sh" "$(command -v ocamlc)" "$prefix/lib/ox_blocking/ox_blocking.cmi" \
  "$assets/compile/global_ok.mli.in" "$assets/compile/global_ok.ml.in" \
  "$assets/compile/local_fail.mli.in" "$assets/compile/local_fail.ml.in"
ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -c main.mli
ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -linkpkg main.ml -o consumer.exe
./consumer.exe
