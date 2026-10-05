#!/usr/bin/env bash
# ^safe-1kqm ^safe-gm8y ^safe-y047: real installed provider, copied fault controls.
set -euo pipefail
[[ $# == 3 ]] || { printf 'usage: %s PREFIX AUDIT FAULT
' "$0" >&2; exit 2; }
prefix=$(realpath -e "$1")
audit=$(realpath -e "$2")
fault=$(realpath -e "$3")
[[ -d "$prefix/lib/ox_http" && -x "$audit" && -x "$fault" ]] || exit 2
outside_checkout() {
  local directory=$1
  while :; do
    [[ ! -e "$directory/.git" && ! -f "$directory/dune-project" ]] || exit 2
    [[ "$directory" != / ]] || break
    directory=$(dirname "$directory")
  done
}
outside_checkout "$prefix"
scratch=$(mktemp -d /var/tmp/ox-codec-provider.XXXXXX)
scratch=$(realpath -e "$scratch")
[[ "$scratch" == /var/tmp/ox-codec-provider.* && -d "$scratch" ]] || exit 2
cleanup() { case "$scratch" in /var/tmp/ox-codec-provider.*) rm -rf -- "$scratch" ;; *) exit 1 ;; esac; }
trap cleanup EXIT
outside_checkout "$scratch"
cp -LR "$prefix/lib/ox_http" "$scratch/provider"
chmod -R u+w "$scratch/provider"
cd "$scratch"
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
ocamlfind query -recursive -format '%d' ox_http yojson > "$scratch/directories"
mapfile -t directories < "$scratch/directories"
include=(-I "$scratch/provider")
for directory in "${directories[@]}"; do
  [[ $(realpath -e "$directory") == "$prefix/lib/ox_http" ]] || include+=(-I "$directory")
done
printf '[@@@ox.domain]
type t = Ox_http.Url.t
val parse : string -> (t, Ox_http.Url.parse_error) result
' > consumer.mli
printf 'type t = Ox_http.Url.t
let parse = Ox_http.Url.parse
' > consumer.ml
ocamlc -bin-annot "${include[@]}" -c consumer.mli
ocamlc -bin-annot "${include[@]}" -c consumer.ml
"$audit" "$scratch/consumer.mli" "$scratch/consumer.cmti"
original="$prefix/lib/ox_http/ox_http__Url.cmt"
target="$scratch/provider/ox_http__Url.cmt"
[[ -f "$original" && -f "$target" && ! -L "$target" ]] || exit 2
expect_unknown() {
  local wanted=$1 rc=0
  "$audit" "$scratch/consumer.mli" "$scratch/consumer.cmti" >out 2>err || rc=$?
  [[ $rc == 1 ]] || { printf 'expected undecided, got exit %s
' "$rc" >&2; sed -n '1,60p' err >&2; exit 1; }
  awk -v wanted="$wanted" '/undecided: required audited evidence for Ox_http__Url:/ && index($0,wanted) {ok=1} END {exit !ok}' err || { sed -n '1,60p' err >&2; exit 1; }
}
# Faults only affect dereferenced scratch copies, never the installed provider.
rm -- "$target"
expect_unknown 'missing'
printf 'malformed provider annotation
' > "$target"
expect_unknown 'malformed'
for mode in source pipeline self; do
  "$fault" "$mode" "$original" "$target"
  case "$mode" in
    source) expect_unknown 'digest' ;;
    pipeline) expect_unknown 'preprocessing' ;;
    self) expect_unknown 'implementation/interface fingerprints differ' ;;
  esac
done
cp -L "$original" "$target"
# Shadow an implementation-only import with a valid but different CMI.
cp -L "$scratch/provider/ox_http__Header.cmi" "$scratch/provider/stdlib__String.cmi"
expect_unknown 'import fingerprint differs'
rm -- "$scratch/provider/stdlib__String.cmi"
"$audit" "$scratch/consumer.mli" "$scratch/consumer.cmti"
# Same package spelling and forged declaration locations do not prove validation.
mkdir counterfeit
cd counterfeit
printf '# 1 "lib/http/url.mli"
type t
val parse : string -> (t, string) result
' > ox_http__Url.mli
printf 'type t = string
let parse text = Ok text
' > ox_http__Url.ml
printf 'module Url = Ox_http__Url
' > ox_http.mli
printf 'module Url = Ox_http__Url
' > ox_http.ml
ocamlc -bin-annot -c ox_http__Url.mli
ocamlc -bin-annot -c ox_http__Url.ml
ocamlc -bin-annot -c ox_http.mli
ocamlc -bin-annot -c ox_http.ml
printf '[@@@ox.domain]
type t = Ox_http.Url.t
val parse : string -> (t, string) result
' > consumer.mli
printf 'type t = Ox_http.Url.t
let parse = Ox_http.Url.parse
' > consumer.ml
ocamlc -bin-annot -I . -c consumer.mli
ocamlc -bin-annot -I . -c consumer.ml
rc=0
"$audit" "$PWD/consumer.mli" "$PWD/consumer.cmti" >out 2>err || rc=$?
[[ $rc == 1 ]] && awk '/undecided: required audited evidence for Ox_http__Url:/ {ok=1} END {exit !ok}' err
cd "$scratch"
mkdir public_impostor
cd public_impostor
printf '# 1 "lib/http/url.mli"
module Url : sig type t val parse : string -> (t, string) result end
' > ox_http.mli
printf 'module Url = struct type t = string let parse text = Ok text end
' > ox_http.ml
ocamlc -bin-annot -c ox_http.mli
ocamlc -bin-annot -c ox_http.ml
printf '[@@@ox.domain]
type t = Ox_http.Url.t
val parse : string -> (t, string) result
' > consumer.mli
printf 'type t = Ox_http.Url.t
let parse = Ox_http.Url.parse
' > consumer.ml
# The authentic private Url provider remains available. A forged public Ox_http
# facade must not borrow its validation proof just by spelling the same public path.
ocamlc -bin-annot -I . "${include[@]}" -c consumer.mli
ocamlc -bin-annot -I . "${include[@]}" -c consumer.ml
rc=0
"$audit" "$PWD/consumer.mli" "$PWD/consumer.cmti" >out 2>err || rc=$?
[[ $rc == 1 ]] && awk '/undecided:/ && /abstract|opaque|proven/ {ok=1} END {exit !ok}' err
printf 'installed codec provider controls passed
'
