#!/usr/bin/env bash
# ^safe-y047 ^nlintcov-q6n2: real Once/Eio artifacts, never adapter admission itself.
set -euo pipefail
probe=$(realpath "$1")
once=$(realpath "$2")/lib/ox
eio=$(ocamlfind query eio)
"$probe" "$once/ox__Once.cmt" "$once/ox__Once.cmti" \
  "$eio/core/eio__core__Cancel.cmt" "$eio/core/eio__core__Fiber.cmt" \
  "$eio/core/eio__core.cmt" "$eio/core/eio__core.cmti" \
  "$eio/eio__Eio_mutex.cmt" "$eio/eio__Eio_mutex.cmti" \
  "$eio/eio__Time.cmt" "$eio/eio__Time.cmti"
scratch=$(mktemp -d /var/tmp/ox-installed-runtime.XXXXXXXX)
case "$scratch" in /var/tmp/ox-installed-runtime.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "${scratch:?}"' EXIT
cp -a "$eio" "$scratch/relocated-eio"
"$probe" "$scratch/relocated-eio/core/eio__core__Cancel.cmt" \
  "$scratch/relocated-eio/eio__Time.cmt"
reject() {
  if "$probe" "$1"; then echo "invalid real installed evidence accepted: $1" >&2; exit 1; fi
}
cp -a "$eio" "$scratch/missing-sibling"
mv "$scratch/missing-sibling/runtime_events/eio_runtime_events.cmt" "$scratch/sibling-hidden"
reject "$scratch/missing-sibling/core/eio__core__Cancel.cmt"
cp -a "$eio" "$scratch/ambiguous-sibling"
printf '%s\n' '(library (modules (singleton (obj_name eio_runtime_events) (visibility public) (source (path Eio_runtime_events) (impl (path runtime_events/eio_runtime_events.ml))))))' \
  >> "$scratch/ambiguous-sibling/dune-package"
reject "$scratch/ambiguous-sibling/core/eio__core__Cancel.cmt"
cp -a "$eio" "$scratch/collision"
mkdir "$scratch/collision/other"
# Two independently owned modules cannot map the same recorded object directory
# to different installed directories, even when both sources and CMIs are genuine.
for file in "$scratch/collision/core"/eio__core__Fiber.*; do
  mv "$file" "$scratch/collision/other/"
done
mv "$scratch/collision/core/fiber.ml" "$scratch/collision/other/fiber.ml"
sed -i 's@core/eio__core__Fiber@other/eio__core__Fiber@g; s@core/fiber.ml@other/fiber.ml@g'   "$scratch/collision/dune-package"
reject "$scratch/collision/eio__Time.cmt"
cp -a "$once" "$scratch/once"
mv "$scratch/once/ox__Once.cmti" "$scratch/peer-hidden"
reject "$scratch/once/ox__Once.cmti"
printf '%s\n' 'real installed artifacts: 10 Once/Eio annotations, relocation and sibling/peer controls: pass'
