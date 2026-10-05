#!/usr/bin/env bash
# ^safe-1kqm ^safe-gm8y ^safe-l2jj: fresh nested-project compiler evidence.
set -euo pipefail
[[ $# == 3 ]] || { printf "usage: %s DRIVER EVIDENCE CANDIDATE_PREFIX\n" "$0" >&2; exit 2; }
driver=$(realpath -e "$1")
evidence=$(realpath -e "$2")
prefix=$(realpath -e "$3")
[[ -x "$driver" && -f "$evidence/dune-project" && -d "$prefix/lib" ]] || exit 2
work=$(mktemp -d /var/tmp/ox-codec-source.XXXXXX)
work=$(realpath -e "$work")
[[ "$work" == /var/tmp/ox-codec-source.* && -d "$work" ]] || exit 2
cleanup() { case "$work" in /var/tmp/ox-codec-source.*) rm -rf -- "$work" ;; *) exit 1 ;; esac; }
trap cleanup EXIT
# Copy authored inputs only, never stale generated wrappers or root CMTs.
cp "$evidence/dune" "$evidence/dune-project" "$evidence/.ocamlformat" \
  "$evidence/"*.ml "$evidence/"*.mli "$work/"
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
cd "$work"
dune build --root "$work" @check
"$driver" "$work"
