#!/usr/bin/env bash
# ^nparse-gb03: paired native compiler controls; public interfaces are compiled first.
# Usage: check-compile.sh OCAMLOPT BLOCKING_CMI OX_CMI EIO_CMI EIO_CORE_CMI POS_MLI POS_ML RAW_MLI RAW_ML
set -eEuo pipefail
[[ "$#" = 9 ]] || exit 2
compiler="$1"
blocking="$(dirname "$(realpath -e "$2")")"
ox="$(dirname "$(realpath -e "$3")")"
eio="$(dirname "$(realpath -e "$4")")"
eio_core="$(dirname "$(realpath -e "$5")")"
positive_mli="$(realpath -e "$6")"
positive_ml="$(realpath -e "$7")"
raw_mli="$(realpath -e "$8")"
raw_ml="$(realpath -e "$9")"
scratch="$(mktemp -d /var/tmp/ox-blocking-concurrency-compile.XXXXXX)"
[[ "$scratch" = /var/tmp/ox-blocking-concurrency-compile.* && -d "$scratch" ]] || exit 2
printf 'native compiler evidence=%s\n' "$scratch"
cp "$positive_mli" "$scratch/positive.mli"
cp "$positive_ml" "$scratch/positive.ml"
cp "$raw_mli" "$scratch/raw.mli"
cp "$raw_ml" "$scratch/raw.ml"
record() {
  local label="$1" rc=0
  shift
  "$@" >"$scratch/$label.log" 2>&1 || rc=$?
  printf '%s\t%d\n' "$label" "$rc" >>"$scratch/status.tsv"
  return "$rc"
}
cd "$scratch"
record positive-interface "$compiler" -I "$blocking" -I "$ox" -I "$eio" -I "$eio_core" -c positive.mli
record positive-native "$compiler" -I "$blocking" -I "$ox" -I "$eio" -I "$eio_core" -c positive.ml
record raw-interface "$compiler" -I "$blocking" -I "$ox" -I "$eio" -I "$eio_core" -c raw.mli
rc=0
record raw-native "$compiler" -I "$blocking" -I "$ox" -I "$eio" -I "$eio_core" -c raw.ml || rc=$?
[[ "$rc" = 2 ]] || { printf 'raw integer control exited %s, expected 2\n' "$rc" >&2; exit 1; }
python3 - "$scratch/raw-native.log" <<'PY'
import pathlib, re, sys
message = pathlib.Path(sys.argv[1]).read_text()
assert 'Error:' in message, message
assert re.search(r'The constant 1 has type\s*"?int"?', message), message
assert re.search(r'expected of type\s*"?Ox\.Concurrency\.t"?', message), message
assert 'Unbound module' not in message and 'Unbound value' not in message, message
PY
printf 'checked native worker bound accepted; raw integer rejected for Ox.Concurrency.t; evidence=%s\n' "$scratch"
