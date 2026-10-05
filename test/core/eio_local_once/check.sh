#!/usr/bin/env bash
# Real native typed bodies, paired controls, physical Cmm and bounded rooting. ^nonce-lrzq ^nonce-mjpe
set -euo pipefail
cases=$(realpath "$1")
compiler=$(realpath "$2")
scripts=$(dirname "$(realpath "$0")")
: "${EIO_LOCAL_ONCE_MANIFEST:?Use nix develop .#eio-local-once; default provider is intentionally unchanged}"
: "${EIO_LOCAL_ONCE_SOURCE:?Missing canonical patched source}"
: "${EIO_LOCAL_ONCE_PATCH:?Missing canonical patch}"
unset EIO_BACKEND
work=$(mktemp -d "${TMPDIR:-/tmp}/ox-eio-local-once.XXXXXX")
logs="${EIO_LOCAL_ONCE_LOG_DIR:-$work/logs}"
mkdir -p "$logs" "$work/native"
cp "$cases/"*.ml "$cases/"*.mli "$work/native/"
python "$scripts/provenance.py" "$compiler" | tee "$logs/provenance.log"
export OCAMLFIND_COMMANDS="ocamlopt=$compiler ocamlc=$(dirname "$compiler")/ocamlc"
cd "$work/native"
for source in good_*.ml bad_*.ml; do
  unit=${source%.ml}
  ocamlfind ocamlopt -package eio.mock -bin-annot -c "$unit.mli" 2>&1 | tee "$logs/$unit-interface.log"
  status=0
  ocamlfind ocamlopt -package eio.mock -bin-annot -dlambda -dcmm -c "$source" >"$logs/$unit-implementation.log" 2>&1 || status=$?
  case "$unit" in good_*) expected=0 ;; bad_*) expected=2 ;; esac
  echo "$unit interface=0 implementation=$status expected=$expected" | tee -a "$logs/native-statuses.log"
  [[ "$status" == "$expected" ]]
  if [[ "$expected" == 2 ]]; then
    grep -aEq '^Error:' "$logs/$unit-implementation.log"
    grep -aEq 'once|many|local|global|escap|already been used' "$logs/$unit-implementation.log"
  fi
done
[[ $(grep -aEc 'alloc_local' "$logs/good_z_physical_callers-implementation.log") -ge 3 ]]
python "$scripts/hostile.py" "$EIO_LOCAL_ONCE_SOURCE" "$work/bodies"
for name in cancel-genuine eio_mutex-genuine cancel-reuse cancel-store mutex-reuse mutex-store; do
  directory="$work/bodies/$name"
  case "$name" in cancel-*) module=cancel; opens=(-open Eio__core__) ;; *) module=eio_mutex; opens=(-open Eio__core -open Eio__core.Private -open Eio__) ;; esac
  case "$name" in *-genuine) expected=0 ;; *) expected=2 ;; esac
  status=0
  (cd "$directory"; ocamlfind ocamlopt -package eio -bin-annot "${opens[@]}" -c "$module.ml") >"$logs/provider-$name.log" 2>&1 || status=$?
  echo "provider $name implementation=$status expected=$expected" | tee -a "$logs/provider-statuses.log"
  [[ "$status" == "$expected" ]]
  if [[ "$expected" == 2 ]]; then
    grep -aEq '^Error:' "$logs/provider-$name.log"
    grep -aEq 'once|local.*global|already been used' "$logs/provider-$name.log"
  fi
done
ocamlfind ocamlopt -package eio.mock,eio_posix,eio_main -bin-annot -c runtime.mli 2>&1 | tee "$logs/runtime-interface.log"
ocamlfind ocamlopt -package eio.mock,eio_posix,eio_main -bin-annot -dlambda -dcmm -c runtime.ml 2>&1 | tee "$logs/runtime-native.log"
[[ $(grep -aEc 'alloc_local' "$logs/runtime-native.log") -ge 3 ]]
ocamlfind ocamlopt -package eio.mock,eio_posix,eio_main -bin-annot -c real_backends.mli 2>&1 | tee "$logs/real-backends-interface.log"
ocamlfind ocamlopt -verbose -package eio.mock,eio_posix,eio_main -linkpkg good_global.cmx good_protect_local.cmx good_mutex_local.cmx good_local_unprotected.cmx good_z_physical_callers.cmx runtime.cmx real_backends.ml -o runtime.exe 2>&1 | tee "$logs/runtime-link.log"
timeout 180 ./runtime.exe | tee "$logs/runtime.log"
for backend in MOCK POSIX MAIN; do
  [[ $(grep -ac "^PASS $backend:" "$logs/runtime.log") == 14 ]]
done
echo 'PASS native MLI/ML controls, actual provider hostile negatives, physical alloc_local, 14 cases per genuine backend'
echo "Evidence: $logs"
