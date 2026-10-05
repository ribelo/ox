#!/usr/bin/env bash
# ^nparse-gb03: genuine installed public worker-bound and existing native-lease proof.
# Usage: check-installed.sh EXTERNAL_PREFIX EXTERNAL_BLOCKING_ASSETS
# Assets contain copied safety_concurrency/ and safety_native_leases/ directories.
set -eEuo pipefail
[[ "$#" = 2 ]] || exit 2
prefix="$(realpath -e "$1")"
assets="$(realpath -e "$2")"
outside_checkout() {
  local directory="$1"
  while :; do
    [[ ! -e "$directory/.git" && ! -f "$directory/dune-project" ]] || {
      printf 'installed proof rejects checkout/build path: %s\n' "$directory" >&2
      exit 2
    }
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
  done
}
outside_checkout "$prefix"
outside_checkout "$assets"
export OCAMLPATH="$prefix/lib"
for package in ox ox_blocking; do
  found="$(realpath -e "$(ocamlfind query "$package")")"
  [[ "$found" = "$prefix/lib/$package" ]] || exit 2
  for artifact in "$found"/*.cmi "$found"/*.cmxa "$found"/*.a; do
    [[ -f "$artifact" ]] || exit 2
    [[ "$(realpath -e "$artifact")" = "$prefix"/* ]] || {
      printf 'installed artifact escapes prefix: %s\n' "$artifact" >&2
      exit 2
    }
  done
done
scratch="$(mktemp -d /var/tmp/ox-blocking-concurrency-installed.XXXXXX)"
[[ "$scratch" = /var/tmp/ox-blocking-concurrency-installed.* && -d "$scratch" ]] || exit 2
outside_checkout "$scratch"
printf 'installed native evidence=%s\n' "$scratch"
record() {
  local label="$1" rc=0
  shift
  "$@" >"$scratch/$label.log" 2>&1 || rc=$?
  printf '%s\t%d\n' "$label" "$rc" >>"$scratch/status.tsv"
  return "$rc"
}
record compiler-version ocamlopt -version
cp "$assets/safety_concurrency/runtime.ml" "$assets/safety_concurrency/runtime.mli" "$scratch/"
printf 'let () = Runtime.run ()\n' >"$scratch/main.ml"
printf '(* installed public native entry point *)\n' >"$scratch/main.mli"
cd "$scratch"
record paired-native bash "$assets/safety_concurrency/check-compile.sh" \
  "$(command -v ocamlopt)" "$prefix/lib/ox_blocking/ox_blocking.cmi" \
  "$prefix/lib/ox/ox.cmi" "$(ocamlfind query eio)/eio.cmi" \
  "$(ocamlfind query eio.core)/eio__core.cmi" \
  "$assets/safety_concurrency/compile/positive.mli.in" \
  "$assets/safety_concurrency/compile/positive.ml.in" \
  "$assets/safety_concurrency/compile/raw.mli.in" \
  "$assets/safety_concurrency/compile/raw.ml.in"
record runtime-interface ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -c runtime.mli
record runtime-native ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -c runtime.ml
record main-interface ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -c main.mli
record native-link ocamlfind ocamlopt -thread -package ox_blocking,eio_main,unix -linkpkg runtime.cmx main.ml -o consumer.exe
record native-run ./consumer.exe
record existing-native-lease-consumer bash "$assets/safety_native_leases/check-installed.sh" \
  "$prefix" "$assets/safety_native_leases"
printf 'installed checked worker concurrency and existing native leases passed; evidence=%s\n' "$scratch"
