#!/usr/bin/env bash
# ^safe-czoe ^safe-y047 ^safe-fr73: locality only; no Unique or must-close claim.
# OxCaml mode templates use .ml.in/.mli.in because stock ocamlformat cannot parse
# them. Fresh .ml/.mli copies are compiled with the matching OxCaml compiler.
# Usage: check-compile.sh OCAMLC BLOCKING_CMI GLOBAL_MLI GLOBAL_ML LOCAL_MLI LOCAL_ML
set -eEuo pipefail
[[ "$#" = 6 ]] || exit 2
compiler="$1"
library="$(dirname "$(realpath -e "$2")")"
global_mli="$(realpath -e "$3")"
global_ml="$(realpath -e "$4")"
local_mli="$(realpath -e "$5")"
local_ml="$(realpath -e "$6")"
scratch="$(mktemp -d "$PWD/native-leases-compile.XXXXXX")"
[[ "$scratch" = "$PWD"/native-leases-compile.* && -d "$scratch" ]] || exit 2
trap 'rm -rf -- "$scratch"' EXIT
cp "$global_mli" "$scratch/global_ok.mli"
cp "$global_ml" "$scratch/global_ok.ml"
cp "$local_mli" "$scratch/local_fail.mli"
cp "$local_ml" "$scratch/local_fail.ml"
cd "$scratch"
"$compiler" -I "$library" -c global_ok.mli
"$compiler" -I "$library" -c global_ok.ml
"$compiler" -I "$library" -c local_fail.mli
if "$compiler" -I "$library" -c local_fail.ml >local.out 2>local.err; then
  printf 'local native borrow unexpectedly captured by global callback
' >&2
  exit 1
fi
python3 - "$scratch/local.err" <<'PY'
import pathlib, sys
message = pathlib.Path(sys.argv[1]).read_text()
assert 'borrow is local to the parent region' in message, message
assert 'expected to be global' in message, message
PY
printf 'global alias accepted; local borrow rejected (no Unique claim)
'
