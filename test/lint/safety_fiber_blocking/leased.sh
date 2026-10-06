#!/usr/bin/env bash
# ^safe-r5ye ^safe-ohen: genuine producer prefix, isolated nested typed consumer.
set -euo pipefail
[[ $# == 2 ]] || { printf "usage: bash leased.sh ABS_PREFIX ABS_PROBE\n" >&2; exit 2; }
prefix=$(realpath "$1")
probe=$(realpath "$2")
[[ -f $prefix/lib/ox_blocking/ox_blocking.mli && -x $probe ]] || exit 2
export OCAMLPATH="${prefix:?}/lib${OCAMLPATH:+:$OCAMLPATH}"
[[ $(ocamlfind query ox_blocking) == "$prefix/lib/ox_blocking" ]] || exit 2
fixtures=$(dirname "${BASH_SOURCE[0]}")/leased_consumer
work=$(mktemp -d /var/tmp/ox-fiber-leased.XXXXXX)
[[ $(realpath "$work") == /var/tmp/ox-fiber-leased.* ]] || exit 2
trap 'rm -rf -- "${work:?}"' EXIT
cp -- "$fixtures/dune-project" "$fixtures/dune" "$fixtures/leased.ml" "$fixtures/leased.mli" "$fixtures/progress.ml" "$fixtures/progress.mli" "$work/"
[[ ! -e $work/.git ]] || exit 2
dune build --root "$work" leased_consumer.cma progress.exe
"$probe" "$work/leased.ml" "$work/_build/default/.leased_consumer.objs/byte/leased.cmt"
timeout 5 "$work/_build/default/progress.exe"
set +e
timeout 1 "$work/_build/default/progress.exe" --owner
status=$?
set -e
[[ $status == 124 ]] || { printf "owner wait failed to retain the domain: %d\n" "$status" >&2; exit 1; }
printf "genuine installed owner blocking and native Counting progress proof passed\n"
