#!/usr/bin/env bash
# ^nderive-s2lt ^nderive-9atb ^nderive-sfta ^nderive-cd80 ^nderive-p4tq
# ^nderive-ufnu ^nderive-e5va: real compiler consumers, rejections and line attribution.
set -euo pipefail
ocamlc="$1"
ppx="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
yojson="$(cd "$(dirname "$3")" && pwd)"
# Dune owns this build-directory output; no source files or shared switch are changed.
work="$(pwd)/compiled"
mkdir -p "$work"

compile() {
  local source="$1" name extension
  name="$(basename "$source")"
  extension=cmo
  if [[ "$source" == *.mli ]]; then extension=cmi; fi
  "$ocamlc" -I "$yojson" -I "$work" -pp "$ppx" -c "$source" \
    -o "$work/${name%.*}.$extension" >"$work/out" 2>&1
}

compiles() {
  if ! compile "$1"; then
    printf 'FAIL: %s should compile\n' "$1"
    cat "$work/out"
    exit 1
  fi
  printf 'ok: %s compiles\n' "$1"
}

fails() {
  if compile "$1"; then
    printf 'FAIL: %s compiled but must be refused\n' "$1"
    exit 1
  fi
  if ! grep -Fq -- "$2" "$work/out"; then
    printf 'FAIL: %s refused for an unrelated reason (expected %s)\n' "$1" "$2"
    cat "$work/out"
    exit 1
  fi
  printf 'ok: %s refused (%s)\n' "$1" "$2"
}

compiles result_name.mli
compiles result_name.ml
compiles ../manual_encoder.mli
compiles ../native_encoders.mli
compiles ../module_codecs.mli
compiles encoder_only.ml
compiles consumer_control.ml
fails decoder_top.ml 'Unbound value Encoder_only.t_of_yojson'
fails decoder_private.ml 'Unbound value Encoder_only.ppx_yojson_decode_t'
fails decoder_nested.ml 'Unbound value Encoder_only.M.t_of_yojson'
fails decoder_abstract.ml 'Unbound value Manual_encoder.t_of_yojson'
fails decoder_signature.ml 'Unbound value Native_encoders.t_of_yojson'
fails decoder_nested_signature.ml 'Unbound value Module_codecs.Only.t_of_yojson'
fails leaked_converter.ml 'Unbound value Module_codecs.yojson_of_t'
fails functor.ml 'inside functors is not supported'
fails functor.mli 'inside functors is not supported'
fails first_class.ml 'inside first-class modules is not supported'
fails private_type.ml 'private types are not supported'
fails gadt.ml 'GADT constructors are not supported'
fails inline_record.mli 'inline record constructors are not supported'

location() {
  local source="$1" pattern="$2" line
  line="$(awk -v pattern="$pattern" '$0 ~ pattern { print NR; exit }' "$source")"
  if [[ -z "$line" ]] || ! grep -Fq -- "File \"$source\", line $line," "$work/out"; then
    printf 'FAIL: %s must attribute error to its original line %s\n' "$source" "$line"
    cat "$work/out"
    exit 1
  fi
  printf 'ok: %s error retains filename and line %s\n' "$source" "$line"
}
fails generated_encoder_location.ml 'Unbound value yojson_of_secret'
location generated_encoder_location.ml 'type t ='
fails generated_decoder_location.ml 'Unbound value secret_of_yojson'
location generated_decoder_location.ml 'type t ='
fails restored_location.ml 'has type string'
location restored_location.ml 'let after'
