#!/usr/bin/env bash
# ^nonce-mjpe: fresh paired negative typed evidence, not a corpus exemption.
set -euo pipefail
compiler=$(realpath "$1")
checker=$(realpath "$2")
guard=$(realpath "$3")
evidence=$(realpath "$4")
scratch=$(realpath "$(mktemp -d /var/tmp/ox-global-alias-proof.XXXXXX)")
case "$scratch" in /var/tmp/ox-global-alias-proof.*) ;; *) exit 2 ;; esac
cleanup() {
  rc=$?
  trap - EXIT
  case "$scratch" in /var/tmp/ox-global-alias-proof.*) ;; *) exit 2 ;; esac
  if [[ $rc == 0 ]]; then rm -rf -- "${scratch:?}"; else printf 'failed alias proof retained: %s\n' "$scratch" >&2; fi
  exit "$rc"
}
trap cleanup EXIT
cp "$evidence/alias_controls.ml" "$evidence/alias_controls.mli" "$scratch/"
cd "$scratch"
"$compiler" -bin-annot -c alias_controls.mli
"$compiler" -bin-annot -c alias_controls.ml
"$checker" "$guard" "$scratch/alias_controls.cmt"
