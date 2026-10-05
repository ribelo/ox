#!/usr/bin/env bash
# ^safe-1kqm ^safe-gm8y ^safe-y047: external installed CLI, exact-root assets.
set -euo pipefail
[[ $# == 2 ]] || { printf 'usage: %s INSTALLED_BIN INSTALLED_SHARE
' "$0" >&2; exit 2; }
engine=$(realpath -e "$1")
assets=$(realpath -e "$2")
prefix=$(dirname "$(dirname "$engine")")
[[ -x "$engine" && "$engine" == "$prefix/bin/ox-lint" && "$assets" == "$prefix/share/ox_lint" ]] || exit 2
outside_checkout() {
  local directory=$1
  while :; do
    [[ ! -e "$directory/.git" && ! -f "$directory/dune-project" ]] || exit 2
    [[ "$directory" != / ]] || break
    directory=$(dirname "$directory")
  done
}
outside_checkout "$prefix"
scratch=$(mktemp -d /var/tmp/ox-codec-installed.XXXXXX)
scratch=$(realpath -e "$scratch")
[[ "$scratch" == /var/tmp/ox-codec-installed.* && -d "$scratch" ]] || exit 2
cleanup() { case "$scratch" in /var/tmp/ox-codec-installed.*) rm -rf -- "$scratch" ;; *) exit 1 ;; esac; }
trap cleanup EXIT
outside_checkout "$scratch"
cd "$scratch"
expect() {
  local expected=$1 rc=0
  shift
  "$engine" --root "$assets" --rules ox-codec-seams "$@" >out 2>err || rc=$?
  [[ $rc == "$expected" ]] || { printf 'expected %s, got %s
' "$expected" "$rc" >&2; sed -n '1,60p' out err >&2; exit 1; }
}
expect 0 --self-check
awk '/^ox-lint --self-check: [0-9]+ rule\(s\), replacement\/violating\/clean\/docs present$/ {ok=1} END {exit !ok}' out
[[ ! -s err ]]
export OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
ocamlfind query -recursive -format '%d' ox_http yojson ox_ai_chat ox_ai_systemone ox_ai_openrouter >directories
mapfile -t directories <directories
include=()
for directory in "${directories[@]}"; do include+=(-I "$directory"); done
for pair in 'clean good' 'violating bad'; do
  read -r kind name <<< "$pair"
  cp "$assets/test/lint/$kind/codec_seams.mli" "$name.mli"
  cp "$assets/test/lint/$kind/codec_seams.ml" "$name.ml"
  chmod u+w "$name.mli" "$name.ml"
  ocamlc -bin-annot "${include[@]}" -c "$name.mli"
  ocamlc -bin-annot "${include[@]}" -c "$name.ml"
done
# Keep original included declaration UIDs; shadow only unselected public values.
# These are the actual installed signatures, not hand-written wire schemas.
cat >protocols.ml <<'OCAML'
module type Chat = module type of Ox_ai_chat.Types
module type SystemOne = module type of Ox_ai_systemone.Types
module type Audio = module type of struct
  include Ox_ai_openrouter.Audio
  let body = ()
  let create = ()
end
module type Embeddings = module type of struct
  include Ox_ai_openrouter.Embeddings
  let create = ()
end
module type Responses = module type of struct
  include Ox_ai_openrouter.Responses
  let create = ()
  let create_text = ()
end
OCAML
{ printf '[@@@ox.domain]\n'; sed -n '1,$p' protocols.ml; } >protocols.mli
ocamlc -bin-annot "${include[@]}" -c protocols.mli
ocamlc -bin-annot "${include[@]}" -c protocols.ml
expect 0 --require-typed "$scratch/protocols.mli"
[[ ! -s out ]]
expect 0 --require-typed "$scratch/good.mli"
[[ ! -s out ]]
expect 1 --require-typed "$scratch/bad.mli"
awk '/ox-codec-seams:/ && /raw Yojson.Safe.t/ {ok=1} END {exit !ok}' out
# An actual AST-mapping compiler PPX cannot erase an authored domain obligation.
mkdir ppx-tool
printf '%s\n' 'open Ast_mapper' 'open Parsetree' \
  'let () = run_main (fun _ -> { default_mapper with signature = (fun self items ->' \
  '  let mapped = default_mapper.signature self items in' \
  '  { mapped with psg_items = List.filter (fun item -> match item.psig_desc with' \
  '  | Psig_attribute a when a.attr_name.txt = "ox.domain" -> false | _ -> true) mapped.psg_items }) })' \
  >ppx-tool/erase.ml
printf '' >ppx-tool/erase.mli
ocamlc -c -o ppx-tool/erase.cmi ppx-tool/erase.mli
ocamlc -I +compiler-libs -I ppx-tool ocamlcommon.cma ppx-tool/erase.ml -o ppx-tool/erase.exe
printf '[@@@ox.domain]\nval publish : Yojson.Safe.t\n' >erased.mli
printf 'let publish = `Null\n' >erased.ml
ocamlc -bin-annot "${include[@]}" -ppx "$scratch/ppx-tool/erase.exe" -c erased.mli
ocamlc -bin-annot "${include[@]}" -ppx "$scratch/ppx-tool/erase.exe" -c erased.ml
# The transformed interface still publishes the real raw type; only the marker goes.
printf '' >retained.mli
printf 'let wire : Yojson.Safe.t = Erased.publish\n' >retained.ml
ocamlc -bin-annot "${include[@]}" -c retained.mli
ocamlc -bin-annot "${include[@]}" -c retained.ml
expect 2 --require-typed "$scratch/erased.mli"
[[ ! -s out ]]
awk '/source domain marker has no matching typed interface evidence/ {ok=1} END {exit !ok}' err
printf '
(* stale consumer evidence *)
' >>good.mli
expect 2 --require-typed "$scratch/good.mli"
awk '/stale|digest|changed/ {ok=1} END {exit !ok}' err
printf '[@@@ox.domain]
type t = Yojson.Safe.t
' >missing.mli
expect 2 --require-typed "$scratch/missing.mli"
[[ -s err ]]
printf 'installed codec-seams CLI controls passed
'
