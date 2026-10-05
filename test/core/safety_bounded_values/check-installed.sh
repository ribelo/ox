#!/usr/bin/env bash
# ^nparse-gb03 ^safe-6ukl ^safe-u2na: real installed public compiler/runtime proof.
# Usage: nix develop -c bash check-installed.sh EXTERNAL_PREFIX [EXTERNAL_ASSETS]
# To prepare the prefix: nix develop -c dune install --prefix /var/tmp/.../prefix
# Copy test/{core,json}/safety_bounded_values to ASSETS/{core,json}; no Dune metadata.
set -eEuo pipefail
[[ "$#" = 1 || "$#" = 2 ]] || { printf 'usage: %s PREFIX [ASSETS]\n' "$0" >&2; exit 2; }
prefix="$(realpath -e "$1")"
assets="$(realpath -e "${2:-$(dirname "$(realpath -e "$0")")/../../..}")"
# Default assets are the repository test tree; external assets use core/ and json/.
if [[ -d "$assets/test/core/safety_bounded_values" ]]; then assets="$assets/test"; fi
outside_git() {
  local directory="$1"
  while :; do
    [[ ! -e "$directory/.git" && ! -f "$directory/dune-project" ]] || {
      printf 'installed proof refuses Git/source ancestry: %s\n' "$directory" >&2; exit 2;
    }
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
  done
}
outside_git "$prefix"
export OCAMLPATH="$prefix/lib"
for package in ox ox_json; do
  found="$(realpath -e "$(ocamlfind query "$package")")"
  [[ "$found" = "$prefix/lib/$package" ]] || { printf 'lookup escaped prefix: %s\n' "$found" >&2; exit 2; }
  for file in "$found"/*.cmi "$found"/*.cmxa "$found"/*.a; do
    [[ -f "$file" ]] || exit 2
    resolved="$(realpath -e "$file")"
    [[ "$resolved" = "$prefix"/* ]] || { printf 'installed artifact escaped prefix: %s\n' "$resolved" >&2; exit 2; }
  done
done
scratch="$(mktemp -d /var/tmp/ox-bounded-installed.XXXXXX)"
[[ -d "$scratch" && "$scratch" = /var/tmp/ox-bounded-installed.* ]] || exit 2
outside_git "$scratch"
mkdir "$scratch/logs"
printf 'evidence=%s\n' "$scratch"
printf 'label\texit_status\n' > "$scratch/status.tsv"
cd "$scratch"
record() {
  local label="$1"; shift
  local rc=0
  "$@" > "$scratch/logs/$label.log" 2>&1 || rc=$?
  printf '%s\t%d\n' "$label" "$rc" >> "$scratch/status.tsv"
  return "$rc"
}
check_compile() {
  local suite="$1" name="$2" expected="$3"
  local directory="$scratch/$suite-$name"
  mkdir "$directory"
  outside_git "$directory"
  cp "$assets/$suite/safety_bounded_values/compile/$name.mli.in" "$directory/probe.mli"
  cp "$assets/$suite/safety_bounded_values/compile/$name.ml.in" "$directory/probe.ml"
  (
    cd "$directory"
    record "$suite-$name-interface" ocamlfind ocamlopt -thread -package ox,ox_json -c probe.mli || return "$?"
    local rc=0
    record "$suite-$name-implementation" ocamlfind ocamlopt -thread -package ox,ox_json -c probe.ml || rc=$?
    if [[ "$expected" = pass ]]; then [[ "$rc" = 0 ]]; else
      [[ "$rc" = 2 ]]
      # Reject type mismatch specifically, not missing modules or dependencies.
      local output="$(< "$scratch/logs/$suite-$name-implementation.log")"
      [[ "$output" = *'Error:'* && "$output" = *'Ox.'* && "$output" = *'type'* ]]
      [[ "$output" != *'Unbound module'* && "$output" != *'Unbound value'* ]]
    fi
  )
}
check_compile core positive pass
for source in "$assets/core/safety_bounded_values/compile/"*.ml.in; do
  name="$(basename "$source" .ml.in)"
  if [[ "$name" != positive ]]; then check_compile core "$name" fail; fi
done
check_compile json positive pass
for name in raw capacity concurrency; do check_compile json "$name" fail; done
for suite in core json; do
  directory="$scratch/native-$suite"
  mkdir "$directory"
  outside_git "$directory"
  cp "$assets/$suite/safety_bounded_values/runtime."{ml,mli} "$directory/"
  printf 'let () = Runtime.run ()\n' > "$directory/main.ml"
  printf '(* installed native runtime entry point *)\n' > "$directory/main.mli"
  (
    cd "$directory"
    record "$suite-native-interface" ocamlfind ocamlopt -thread -package ox,ox_json,yojson -c runtime.mli
    record "$suite-native-runtime" ocamlfind ocamlopt -thread -package ox,ox_json,yojson -c runtime.ml
    record "$suite-native-main-interface" ocamlfind ocamlopt -thread -package ox,ox_json,yojson -c main.mli
    record "$suite-native-link" ocamlfind ocamlopt -thread -package ox,ox_json,yojson -linkpkg runtime.cmx main.ml -o consumer.exe
    record "$suite-native-run" ./consumer.exe
  )
done
printf 'all installed bounded-value controls passed; evidence=%s\n' "$scratch"
