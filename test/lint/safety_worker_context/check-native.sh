#!/usr/bin/env bash
# ^safe-sr6e ^safe-9hbm ^safe-eftp: genuine MI-first native candidate evidence.
set -euo pipefail
driver=$(realpath "$1"); blocking=$(realpath "$2"); ox=$(realpath "$3")
fixtures=$(realpath "$(dirname "$0")/native_consumer")
consumer=$(mktemp -d /var/tmp/ox-eio-candidates.XXXXXXXX)
cp "$fixtures"/{catalogue_pairs.ml,catalogue_pairs.mli,boundary_pairs.ml,boundary_pairs.mli} "$consumer/"
(
  cd "$consumer"
  for unit in catalogue_pairs boundary_pairs; do
    ocamlfind ocamlopt -thread -package eio -I "$blocking" -I "$ox" -bin-annot -c "$unit.mli"
    ocamlfind ocamlopt -thread -package eio -I "$blocking" -I "$ox" -bin-annot -c "$unit.ml"
    [[ -f "$unit.cmti" && -f "$unit.cmx" && -f "$unit.o" && -f "$unit.cmt" ]]
    "$driver" "$consumer/$unit.cmt" "$consumer/$unit.ml"
  done
)
printf 'native Eio candidate proof passed: %s\n' "$consumer"
